output "this_cert_arn" {
  description = "The ARN of the ACM certificate for the specified zone."
  value       = aws_acm_certificate.this_cert.arn
}