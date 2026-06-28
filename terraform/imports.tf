# The Lambda runtime auto-creates each function's log group on first invocation
# (with infinite retention), so Terraform's plain "create" conflicts with the
# already-existing group. These import blocks bring the existing groups into
# state so Terraform manages their retention (30 days) instead of trying to
# create them.
#
# Safe to leave in place: once a group is in state the import is a no-op, and it
# self-heals the state if a group is ever deleted out of band.
import {
  to = aws_cloudwatch_log_group.morning_config
  id = "/aws/lambda/netzero-morning-config"
}

import {
  to = aws_cloudwatch_log_group.evening_config
  id = "/aws/lambda/netzero-evening-config"
}
