# Shared SDK procedures; definitions only, with dependencies resolved at call time.

proc eq {a b} { string equal $a $b }

proc ne {a b} { ! [eq $a $b] }
