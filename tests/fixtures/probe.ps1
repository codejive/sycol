$mode=$args[0]
switch ($mode) {
    args { for ($i=1; $i -lt $args.Count; $i++) { [Console]::Out.Write('<'+$args[$i]+'>') }; [Console]::Out.Write("`n") }
    newlines { [Console]::Out.Write("line`n`n") }
    carriage { [Console]::Out.Write("line`r") }
    fail { [Console]::Error.WriteLine('diagnostic'); exit 7 }
    capture { [Console]::Out.Write("out ; [literal] {x} \ `"`r`n`n"); [Console]::Error.Write("err`r`n`n"); exit ([int]$args[1]) }
    empty { exit ([int]$args[1]) }
    large { for ($i=0; $i -lt 4096; $i++) { [Console]::Out.Write('0123456789abcdef0123456789abcdef'); [Console]::Error.Write('fedcba9876543210fedcba9876543210') } }
    cwd { [Console]::Out.WriteLine((Get-Location).ProviderPath) }
}
