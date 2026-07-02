# list of objects (key, value, and optional 'tier' to set a param as Advanced if it's > 4096 bytes)
variable "parameters" { type = list(any) }

# using a static parameter_count prevents issues with list interpolation when terraform calculates "count"
variable "parameter_count" { type = string }

# parameters will be stored under key /cassandra/${account_name}/${vpc_name}/${cluster_name}/${parameters[].key}
variable "cluster_name" { type = string }
variable "vpc_name" { type = string }
variable "account_name" { type = string }
