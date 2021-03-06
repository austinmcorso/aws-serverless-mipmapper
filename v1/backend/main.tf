provider "aws" {
  region = "${var.aws_region}"
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
}

# IAM
resource "aws_iam_role" "lambda_role" {
    name = "lambda"
    assume_role_policy = <<EOF
{
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "lambda_store_image_policy" {
    name = "lambda_upload_store_image_policy"
    path = "/"
    description = "My test policy"
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
          "logs:*"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Action": [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:ListBucket",
          "s3:GetObject"
      ],
      "Effect": "Allow",
      "Resource": "${aws_s3_bucket.client.arn}/images/*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_s3_policy_attachment" {
    role = "${aws_iam_role.lambda_role.name}"
    policy_arn = "${aws_iam_policy.lambda_store_image_policy.arn}"
}

# LAMDA
resource "aws_lambda_function" "upload_image_lambda_function" {
  filename = "mipmapper.zip"
  function_name = "upload_image"
  role = "${aws_iam_role.lambda_role.arn}"
  handler = "index.upload"
  runtime = "nodejs4.3"
  source_code_hash = "${base64sha256(file("./mipmapper.zip"))}"
}

resource "aws_lambda_function" "get_upload_url_lambda_function" {
  filename = "mipmapper.zip"
  function_name = "get_upload_url"
  role = "${aws_iam_role.lambda_role.arn}"
  handler = "index.getUploadUrl"
  runtime = "nodejs4.3"
  source_code_hash = "${base64sha256(file("./mipmapper.zip"))}"
}

resource "aws_lambda_function" "process_image_lambda_function" {
  filename = "mipmapper.zip"
  function_name = "process_image"
  role = "${aws_iam_role.lambda_role.arn}"
  handler = "index.processImage"
  runtime = "nodejs4.3"
  timeout = 10
  memory_size = 256 // higher memory, will allocate higher cpu to speed this up
  source_code_hash = "${base64sha256(file("./mipmapper.zip"))}"
}

# API GATEWAY
resource "aws_api_gateway_rest_api" "mipmapper_api" {
  name = "mipmapper_api"
  description = "API for Mipmapper"
  depends_on = [
    "aws_lambda_function.upload_image_lambda_function",
    "aws_lambda_function.process_image_lambda_function"
  ]
  binary_media_types = [
    "image/png",
    "image/jpeg",
    "image/jpg"
  ]
}

# API GATEWAY :: RESOURCES
resource "aws_api_gateway_resource" "upload_image_api_gateway_resource" {
  rest_api_id = "${aws_api_gateway_rest_api.mipmapper_api.id}"
  parent_id = "${aws_api_gateway_rest_api.mipmapper_api.root_resource_id}"
  path_part = "images"
}
resource "aws_api_gateway_resource" "get_upload_url_api_gateway_resource" {
  rest_api_id = "${aws_api_gateway_rest_api.mipmapper_api.id}"
  parent_id = "${aws_api_gateway_resource.upload_image_api_gateway_resource.id}"
  path_part = "v2"
}

# API GATEWAY :: REQUEST METHODS
resource "aws_api_gateway_method" "upload_image_api_gateway_method" {
  rest_api_id = "${aws_api_gateway_rest_api.mipmapper_api.id}"
  resource_id = "${aws_api_gateway_resource.upload_image_api_gateway_resource.id}"
  http_method = "POST"
  authorization = "NONE"
}
resource "aws_api_gateway_method" "upload_image__options" {
  rest_api_id = "${aws_api_gateway_rest_api.mipmapper_api.id}"
  resource_id = "${aws_api_gateway_resource.upload_image_api_gateway_resource.id}"
  http_method = "OPTIONS"
  authorization = "NONE"
}
resource "aws_api_gateway_method" "get_upload_url_api_gateway_method" {
  rest_api_id = "${aws_api_gateway_rest_api.mipmapper_api.id}"
  resource_id = "${aws_api_gateway_resource.get_upload_url_api_gateway_resource.id}"
  http_method = "POST"
  authorization = "NONE"
}

# API GATEWAY :: REQUEST INTEGRATIONS
resource "aws_api_gateway_integration" "upload_image_api_gateway_integration" {
  rest_api_id = "${aws_api_gateway_rest_api.mipmapper_api.id}"
  resource_id = "${aws_api_gateway_resource.upload_image_api_gateway_resource.id}"
  http_method = "${aws_api_gateway_method.upload_image_api_gateway_method.http_method}"
  type = "AWS"
  integration_http_method = "${aws_api_gateway_method.upload_image_api_gateway_method.http_method}"
  uri = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.upload_image_lambda_function.arn}/invocations"
  passthrough_behavior = "WHEN_NO_TEMPLATES"
  content_handling = "CONVERT_TO_TEXT"
  request_templates {
   "image/png" = <<EOF
{
  "imageType": "png",
  "base64Image" : "$input.body"
}
EOF
  "image/jpeg" = <<EOF
{
  "imageType": "jpg",
  "base64Image" : "$input.body"
}
EOF
  "image/jpg" = <<EOF
{
  "imageType": "jpg",
  "base64Image" : "$input.body"
}
EOF
 }
}
resource "aws_api_gateway_integration" "upload_image__options" {
  rest_api_id = "${aws_api_gateway_rest_api.mipmapper_api.id}"
  resource_id = "${aws_api_gateway_resource.upload_image_api_gateway_resource.id}"
  http_method = "${aws_api_gateway_method.upload_image__options.http_method}"
  integration_http_method = "${aws_api_gateway_method.upload_image_api_gateway_method.http_method}"
  type = "MOCK"
  request_templates = {
    "application/json" = <<EOF
{ "statusCode": 200 }
EOF
  }
}
resource "aws_api_gateway_integration" "get_upload_url_api_gateway_integration" {
  rest_api_id = "${aws_api_gateway_rest_api.mipmapper_api.id}"
  resource_id = "${aws_api_gateway_resource.get_upload_url_api_gateway_resource.id}"
  http_method = "${aws_api_gateway_method.get_upload_url_api_gateway_method.http_method}"
  integration_http_method = "${aws_api_gateway_method.upload_image_api_gateway_method.http_method}"
  type = "AWS"
  uri = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_upload_url_lambda_function.arn}/invocations"
}

# API GATEWAY :: RESPONSE INTEGRATIONS
resource "aws_api_gateway_integration_response" "upload_image_api_gateway_integration_response" {
  rest_api_id = "${aws_api_gateway_rest_api.mipmapper_api.id}"
  resource_id = "${aws_api_gateway_resource.upload_image_api_gateway_resource.id}"
  http_method = "${aws_api_gateway_method.upload_image_api_gateway_method.http_method}"
  status_code = "${aws_api_gateway_method_response.upload_image_200.status_code}"
  response_parameters = { "method.response.header.Access-Control-Allow-Origin" = "'*'" }
  depends_on = ["aws_api_gateway_integration.upload_image_api_gateway_integration"]
}
resource "aws_api_gateway_integration_response" "upload_image__options" {
  rest_api_id = "${aws_api_gateway_rest_api.mipmapper_api.id}"
  resource_id = "${aws_api_gateway_resource.upload_image_api_gateway_resource.id}"
  http_method = "${aws_api_gateway_method.upload_image__options.http_method}"
  status_code = "${aws_api_gateway_method_response.upload_image__options_200.status_code}"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'",
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS,GET'",
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
  depends_on = ["aws_api_gateway_integration.upload_image__options"]
}
resource "aws_api_gateway_integration_response" "get_upload_url_api_gateway_integration_response" {
  rest_api_id = "${aws_api_gateway_rest_api.mipmapper_api.id}"
  resource_id = "${aws_api_gateway_resource.get_upload_url_api_gateway_resource.id}"
  http_method = "${aws_api_gateway_method.get_upload_url_api_gateway_method.http_method}"
  status_code = "${aws_api_gateway_method_response.get_upload_url_200.status_code}"
  response_parameters = { "method.response.header.Access-Control-Allow-Origin" = "'*'" }
  depends_on = ["aws_api_gateway_integration.get_upload_url_api_gateway_integration"]
}

# API GATEWAY :: RESPONSE METHODS
resource "aws_api_gateway_method_response" "upload_image_200" {
  rest_api_id = "${aws_api_gateway_rest_api.mipmapper_api.id}"
  resource_id = "${aws_api_gateway_resource.upload_image_api_gateway_resource.id}"
  http_method = "${aws_api_gateway_method.upload_image_api_gateway_method.http_method}"
  status_code = "200"
  response_models = { "application/json" = "Empty" }
  response_parameters = { "method.response.header.Access-Control-Allow-Origin" = true }
}
resource "aws_api_gateway_method_response" "upload_image__options_200" {
  rest_api_id = "${aws_api_gateway_rest_api.mipmapper_api.id}"
  resource_id = "${aws_api_gateway_resource.upload_image_api_gateway_resource.id}"
  http_method = "${aws_api_gateway_method.upload_image__options.http_method}"
  status_code = "200"
  response_models = { "application/json" = "Empty" }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}
resource "aws_api_gateway_method_response" "get_upload_url_200" {
  rest_api_id = "${aws_api_gateway_rest_api.mipmapper_api.id}"
  resource_id = "${aws_api_gateway_resource.get_upload_url_api_gateway_resource.id}"
  http_method = "${aws_api_gateway_method.get_upload_url_api_gateway_method.http_method}"
  status_code = "200"
  response_models = { "application/json" = "Empty" }
  response_parameters = { "method.response.header.Access-Control-Allow-Origin" = true }
}

# API GATEWAY :: DEPLOYMENT STAGES
resource "aws_api_gateway_deployment" "production" {
  rest_api_id = "${aws_api_gateway_rest_api.mipmapper_api.id}"
  stage_name = "prod"
  depends_on = [
    "aws_api_gateway_integration.upload_image_api_gateway_integration",
    "aws_api_gateway_integration.get_upload_url_api_gateway_integration"
  ]
}

# S3
resource "aws_s3_bucket" "client" {
    bucket = "${var.aws_s3_bucket_name}"
    acl = "public-read"

    cors_rule {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
    }
    website {
      index_document = "index.html"
    }
}
resource "aws_lambda_permission" "allow_s3" {
    statement_id = "AllowExecutionFromS3Bucket"
    action = "lambda:InvokeFunction"
    function_name = "${aws_lambda_function.process_image_lambda_function.arn}"
    principal = "s3.amazonaws.com"
    source_arn = "${aws_s3_bucket.client.arn}"
}
resource "aws_lambda_permission" "upload_image_apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.upload_image_lambda_function.function_name}"
  principal     = "apigateway.amazonaws.com"
}

resource "aws_lambda_permission" "get_upload_url_apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.get_upload_url_lambda_function.function_name}"
  principal     = "apigateway.amazonaws.com"
}

resource "aws_s3_bucket_notification" "upload" {
    bucket = "${aws_s3_bucket.client.id}"
    lambda_function {
        lambda_function_arn = "${aws_lambda_function.process_image_lambda_function.arn}"
        events = ["s3:ObjectCreated:*"]
        filter_prefix = "images/orig"
    }
}
