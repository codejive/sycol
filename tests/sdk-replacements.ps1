# Test-side selection, before SDK loading; never loaded by production.
if ($env:SYCOL_TEST_SDK_NATIVE) {
    if ($env:SYCOL_TEST_SDK_NATIVE -cnotin @('fallback','scalars','lists')) { throw 'invalid SYCOL_TEST_SDK_NATIVE' }
    foreach ($name in @('incr','append','concat','lappend')) {
        $keep=($env:SYCOL_TEST_SDK_NATIVE -ceq 'scalars' -and $name -cin @('incr','append')) -or
            ($env:SYCOL_TEST_SDK_NATIVE -ceq 'lists' -and $name -cin @('concat','lappend'))
        if (!$keep) { $script:Sy.Native.Remove($name) }
    }
}
