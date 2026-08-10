#!/bin/bash

# Проверяем, передан ли файл в качестве аргумента
if [ -z "$1" ]; then
    echo "Использование: $0 <имя_файла>"
    echo "Пример: ./restore.sh code"
    exit 1
fi

INPUT_FILE=$1
current_file=""
content_buffer=""

# Функция для записи накопленного содержимого в файл
write_content_to_file() {
    if [ -n "$current_file" ]; then
        # Создаем директорию, если она не существует
        mkdir -p "$(dirname "$current_file")"
        # Записываем содержимое в файл
        echo -n "$content_buffer" > "$current_file"
        echo "Восстановлен файл: $current_file"
    fi
}

# Читаем входной файл построчно
while IFS= read -r line || [ -n "$line" ]; do
    # Ищем строку-заголовок файла, например "============= lib/main.dart ==="
    if [[ "$line" =~ ^=============[[:space:]]([^[:space:]]+)[[:space:]]===+$ ]]; then
        # Сначала записываем содержимое предыдущего файла
        write_content_to_file
        
        # Начинаем обработку нового файла
        current_file="${BASH_REMATCH[1]}"
        content_buffer="" # Очищаем буфер
    # Игнорируем строки "ФАЙЛ НЕ НАЙДЕН"
    elif [[ "$line" =~ ^===[[:space:]].*[[:space:]]\(ФАЙЛ\ НЕ\ НАЙДЕН\)[[:space:]]===+$ ]]; then
        write_content_to_file
        current_file="" # Сбрасываем имя текущего файла
        content_buffer=""
    # Если мы внутри блока содержимого файла
    elif [ -n "$current_file" ]; then
        # Добавляем строку в буфер (с сохранением переноса строки)
        if [ -z "$content_buffer" ]; then
          content_buffer="$line"
        else
          content_buffer="$content_buffer"$'\n'"$line"
        fi
    fi
done < "$INPUT_FILE"

# Записываем содержимое самого последнего файла
write_content_to_file

echo "Восстановление завершено."
