$mode=$args[0]
switch ($mode) {
    args { for ($i=1; $i -lt $args.Count; $i++) { [Console]::Out.Write('<'+$args[$i]+'>') }; [Console]::Out.WriteLine() }
    newlines { [Console]::Out.Write("line`n`n") }
    carriage { [Console]::Out.Write("line`r") }
    fail { [Console]::Error.WriteLine('diagnostic'); exit 7 }
    cwd { [Console]::Out.WriteLine((Get-Location).ProviderPath) }
}
