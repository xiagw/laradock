#!/bin/bash
f1() {
    # 假设这是你的数组
    my_array=(redis mysql php-fpm spring nginx redis mysql php-fpm spring nginx)

    # 使用awk来去重
    unique_array=($(printf "%s\n" "${my_array[@]}" | awk '!seen[$0]++'))

    # 打印结果
    printf "%s " "${unique_array[@]}"
    echo
}
f2() {
    # 假设这是你的数组
    # my_array=(1 2 3 2 4 3 5)
    my_array=(redis mysql php-fpm spring nginx redis mysql php-fpm spring nginx)

    # 排序后使用uniq去重
    unique_array=($(printf "%s\n" "${my_array[@]}" | sort | uniq))

    # 打印结果
    printf "%s " "${unique_array[@]}"
    echo
}

f3() {
    # 定义一个函数用来检查元素是否已经存在于数组中
    contains_element() {
        local e match="$1"
        shift
        for e; do [[ "$e" == "$match" ]] && return 0; done
        return 1
    }

    # 追加新元素并去重
    append_unique_elements() {
        # 新的元素列表
        local new_elements=("mno" "pqr" "abc" "stu")

        for elem in "${new_elements[@]}"; do
            if ! contains_element "$elem" "${arr[@]}"; then
                arr+=("$elem") # 如果不存在则追加
            fi
        done
    }
 set -x
    arr=("abc" "edf" "ghi" "jkl")
    # 使用函数
    append_unique_elements

    # 输出结果
    printf "%s\n" "${arr[@]}"
}
set -x
    args=()
    if [ "$#" -eq 0 ] || { [ "$#" -eq 1 ] && [ "$1" = key ]; }; then
        echo "not found arguments, with default args \"redis mysql php-fpm spring nginx\"."
        args+=(redis mysql php-fpm spring nginx)
        arg_group=1
    fi
