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
    ManagedBy        = "terraform"
    CreatedBy        = "openclaw"
    Environment      = "prod"
    Name             = "axway-team-api-new"
    PortalVisibility = "internal"
    PortalProduct    = "private"
  }
}

resource "aws_api_gateway_rest_api" "new_api" {
  name        = "axway-team-api-new"
  description = "axway-team-api-new REST API managed by OpenClaw"
  tags        = local.tags

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "new_items" {
  rest_api_id = aws_api_gateway_rest_api.new_api.id
  parent_id   = aws_api_gateway_rest_api.new_api.root_resource_id
  path_part   = "items"
}

resource "aws_api_gateway_method" "new_items_get" {
  rest_api_id      = aws_api_gateway_rest_api.new_api.id
  resource_id      = aws_api_gateway_resource.new_items.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "new_items_get" {
  rest_api_id = aws_api_gateway_rest_api.new_api.id
  resource_id = aws_api_gateway_resource.new_items.id
  http_method = aws_api_gateway_method.new_items_get.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({ statusCode = 200 })
  }
}

resource "aws_api_gateway_method_response" "new_items_get_200" {
  rest_api_id = aws_api_gateway_rest_api.new_api.id
  resource_id = aws_api_gateway_resource.new_items.id
  http_method = aws_api_gateway_method.new_items_get.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "new_items_get_200" {
  rest_api_id = aws_api_gateway_rest_api.new_api.id
  resource_id = aws_api_gateway_resource.new_items.id
  http_method = aws_api_gateway_method.new_items_get.http_method
  status_code = aws_api_gateway_method_response.new_items_get_200.status_code

  response_templates = {
    "application/json" = jsonencode({ message = "TODO: connect real backend" })
  }
}

resource "aws_api_gateway_deployment" "new_api" {
  rest_api_id = aws_api_gateway_rest_api.new_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.new_items.id,
      aws_api_gateway_method.new_items_get.id,
      aws_api_gateway_integration.new_items_get.id,
    ]))
  }

  lifecycle { create_before_destroy = true }
}

resource "aws_api_gateway_stage" "new_api_prod" {
  rest_api_id   = aws_api_gateway_rest_api.new_api.id
  deployment_id = aws_api_gateway_deployment.new_api.id
  stage_name    = "prod"

  tags = local.tags
}

resource "aws_api_gateway_usage_plan" "new_api" {
  name        = "axway-team-api-new-usage-plan"
  description = "Usage plan for axway-team-api-new"

  api_stages {
    api_id = aws_api_gateway_rest_api.new_api.id
    stage  = aws_api_gateway_stage.new_api_prod.stage_name
  }

  throttle_settings {
    rate_limit  = 100
    burst_limit = 50
  }

  tags = local.tags
}

resource "aws_api_gateway_api_key" "new_api" {
  name    = "axway-team-api-new-key"
  enabled = true
  tags    = local.tags
}

resource "aws_api_gateway_usage_plan_key" "new_api" {
  key_id        = aws_api_gateway_api_key.new_api.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.new_api.id
}

output "new_api_id" { value = aws_api_gateway_rest_api.new_api.id }
output "new_api_invoke_url" { value = aws_api_gateway_stage.new_api_prod.invoke_url }
output "new_api_key_id" { value = aws_api_gateway_api_key.new_api.id }
output "new_api_key_value" {
  value     = aws_api_gateway_api_key.new_api.value
  sensitive = true
}
output "new_api_usage_plan_id" { value = aws_api_gateway_usage_plan.new_api.id }
