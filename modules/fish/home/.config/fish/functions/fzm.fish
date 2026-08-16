function fzm
    set marks_file ~/.fzf-marks
    if not test -f $marks_file
        touch $marks_file
    end

    if test (count $argv) -gt 0
        if test $argv[1] = "add"
            if test (count $argv) -lt 3
                echo "用法: fzm add <名称> <路径>"
                return 1
            end
            set name $argv[2]
            set path $argv[3]
            if test -d $path
                echo "$name : $path" >> $marks_file
                echo "已添加: $name -> $path"
            else
                echo "路径不存在: $path"
                return 1
            end
        else if test $argv[1] = "list"
            cat $marks_file
        else if test $argv[1] = "delete"
            if test (count $argv) -lt 2
                echo "用法: fzm delete <名称>"
                return 1
            end
            set name $argv[2]
grep -v "^$name :" $marks_file > {$marks_file}.tmp
mv {$marks_file}.tmp $marks_file
            echo "已删除: $name"
        else
            echo "未知命令: $argv[1]"
            echo "用法: fzm [add|list|delete]"
            return 1
        end
        return
    end

    # 交互式选择
    set selected (cat $marks_file | fzf --height 40% --reverse --prompt="> ")
    if test -n "$selected"
        set path (echo $selected | awk -F' : ' '{print $2}')
        if test -d "$path"
            cd "$path"
        else
            echo "路径不存在: $path"
            return 1
        end
    end
end
