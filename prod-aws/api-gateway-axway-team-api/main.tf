terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  cloud {
    organization = "marsmovers"
    workspaces { name = "prod-aws" }
  }
}

provider "aws" { region = "us-east-1" }

locals {
  tags = {
    ManagedBy   = "terraform"
    CreatedBy   = "openclaw"
    Environment = "prod"
    Name        = "axway-team-api"
    PortalVisibility = "internal"
    PortalProduct = "private"
  }
}

# ─── IAM Role for API Gateway CloudWatch Logging ───────────────────────────
resource "aws_iam_role" "apigw_cloudwatch" {
  name = "axway-team-api-apigw-cw-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "apigateway.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "apigw_cloudwatch" {
  role       = aws_iam_role.apigw_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.apigw_cloudwatch.arn
}

# ─── CloudWatch Log Group ──────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "apigw" {
  name              = "/aws/apigateway/axway-team-api"
  retention_in_days = 30
  tags              = local.tags
}

# ─── REST API ──────────────────────────────────────────────────────────────
resource "aws_api_gateway_rest_api" "this" {
  name        = "axway-team-api"
  description = "axway-team-api REST API managed by OpenClaw"
  tags        = local.tags

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# ─── Client Certificate ────────────────────────────────────────────────────
# ─── Resource + Method (MOCK — TODO: replace with real integration) ────────
resource "aws_api_gateway_resource" "items" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "items"
}

resource "aws_api_gateway_method" "items_get" {
  rest_api_id      = aws_api_gateway_rest_api.this.id
  resource_id      = aws_api_gateway_resource.items.id
  http_method      = "GET"
  authorization    = "COGNITO_USER_POOLS"
  authorizer_id    = aws_api_gateway_authorizer.cognito.id
  api_key_required = false
}

resource "aws_api_gateway_authorizer" "cognito" {
  name          = "axway-team-api-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.this.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.axway.arn]
}

resource "aws_cognito_user_pool" "axway" {
  name = "axway-team-api-user-pool"
  tags = local.tags
}

resource "aws_cognito_user_pool_client" "axway" {
  name         = "axway-team-api-client"
  user_pool_id = aws_cognito_user_pool.axway.id

  generate_secret = false
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
  ]
}

resource "aws_api_gateway_integration" "items_get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.items.id
  http_method = aws_api_gateway_method.items_get.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({ statusCode = 200 })
  }
}

resource "aws_api_gateway_method_response" "items_get_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.items.id
  http_method = aws_api_gateway_method.items_get.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "items_get_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.items.id
  http_method = aws_api_gateway_method.items_get.http_method
  status_code = aws_api_gateway_method_response.items_get_200.status_code

  response_templates = {
    "application/json" = <<-EOT
    {
      "message": "TODO: connect real backend",
      "requestHeaders": $input.json('$input.params().header'),
      "apiVersion": {
        "api": "axway-team-api",
        "stage": "$context.stage",
        "resource": "/axway/items",
        "method": "$context.httpMethod"
      }
    }
    EOT
  }
}

# ─── Deployment + Stage ────────────────────────────────────────────────────
resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.items.id,
      aws_api_gateway_method.items_get.id,
      aws_api_gateway_integration.items_get.id,
    ]))
  }

  lifecycle { create_before_destroy = true }
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = "prod"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw.arn
    format         = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  depends_on = [aws_api_gateway_account.this]
  tags       = local.tags
}

resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  method_path = "*/*"

  settings {
    logging_level      = "INFO"
    metrics_enabled    = true
    data_trace_enabled = true
  }
}

# ─── Usage Plan + API Key ──────────────────────────────────────────────────
resource "aws_api_gateway_usage_plan" "this" {
  name        = "axway-team-api-usage-plan"
  description = "Usage plan for axway-team-api"

  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  throttle_settings {
    rate_limit  = 100
    burst_limit = 50
  }

  tags = local.tags
}

resource "aws_api_gateway_api_key" "this" {
  name    = "axway-team-api-key"
  enabled = true
  tags    = local.tags
}

resource "aws_api_gateway_usage_plan_key" "this" {
  key_id        = aws_api_gateway_api_key.this.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.this.id
}

# ─── Outputs ───────────────────────────────────────────────────────────────
output "api_id" {
  value = aws_api_gateway_rest_api.this.id
}

output "api_invoke_url" {
  value = aws_api_gateway_stage.prod.invoke_url
}

output "api_key_id" {
  value = aws_api_gateway_api_key.this.id
}

output "api_key_value" {
  value     = aws_api_gateway_api_key.this.value
  sensitive = true
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.axway.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.axway.id
}

output "cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.apigw.name
}

output "usage_plan_id" {
  value = aws_api_gateway_usage_plan.this.id
}
