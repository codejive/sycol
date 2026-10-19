# Test-side selection only. Source after the interpreter, before SDK loading.
# Empty/default keeps all replacements; fallback/scalars/lists select subsets.
case ${SYCOL_TEST_SDK_NATIVE-} in
    '') ;;
    fallback|scalars|lists)
        sdk_names=(); sdk_handlers=()
        for ((sdk_i=0;sdk_i<${#NN[@]};sdk_i++)); do
            case ${NN[sdk_i]} in
                incr|append) [[ $SYCOL_TEST_SDK_NATIVE == scalars ]] || continue;;
                concat|lappend) [[ $SYCOL_TEST_SDK_NATIVE == lists ]] || continue;;
            esac
            sdk_names+=("${NN[sdk_i]}"); sdk_handlers+=("${NH[sdk_i]}")
        done
        NN=("${sdk_names[@]}"); NH=("${sdk_handlers[@]}")
        unset sdk_names sdk_handlers sdk_i;;
    *) printf '%s\n' 'invalid SYCOL_TEST_SDK_NATIVE' >&2; exit 1;;
esac
