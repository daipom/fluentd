$ErrorActionPreference = "Stop"
Set-PSDebug -Trace 1

Select-String -Path "fluent.conf" -Pattern "foo" -SimpleMatch -Quiet
Select-String -Path "fluent.conf" -Pattern "foo", "bar" -SimpleMatch -Quiet
Select-String -Path "fluent.conf" -SimpleMatch -Quiet -Pattern "foo", "bar"
Select-String -Path "fluent.conf" -SimpleMatch -Pattern "foo", "bar"
Select-String -Path "fluent.conf" -SimpleMatch -Pattern "foo", "bar", "bind"
Select-String -Path "fluent.conf" -SimpleMatch -Quiet -Pattern "foo", "bar", "bind"

Select-String -Path "fluent.conf" -Pattern "[warn]", "[error]", "[fatal]" -SimpleMatch -Quiet
Select-String -Path "fluent.conf" -SimpleMatch -Quiet -Pattern "[warn]", "[error]", "[fatal]"

Select-String -Path "fluent.conf" -SimpleMatch -Quiet -Pattern "warn", "error", "fatal"
Select-String -Path "fluent.conf" -SimpleMatch -Quiet -Pattern "[warn]", "[fatal]"
Select-String -Path "fluent.conf" -SimpleMatch -Quiet -Pattern "[foo]", "[bar]", "[boo]"
