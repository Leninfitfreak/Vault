variable "policies" {
  description = "Vault policies keyed by policy name."
  type = map(object({
    rules = string
  }))
  default = {}
}
