variable "mounts" {
  description = "KV v2 mounts keyed by mount path."
  type = map(object({
    description = string
  }))
  default = {}
}
