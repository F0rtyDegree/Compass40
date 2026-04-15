#!/bin/bash

# Список всех файлов в нужном порядке
files=(
    "pubspec.yaml"
    "analysis_options.yaml"
    "android/app/src/main/AndroidManifest.xml"
)

# Добавить все Dart файлы из lib/
while IFS= read -r file; do
    files+=("$file")
done < <(find lib -type f -name "*.dart" | sort)

# Добавить все Dart и Kotlin файлы из packages/
while IFS= read -r file; do
    files+=("$file")
done < <(find packages -type f \( -name "*.dart" -o -name "*.kt" \) | sort)

# Вывести все файлы
for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "=== $file ==="
        cat -n "$file"
        echo ""
    else
        echo "=== $file (ФАЙЛ НЕ НАЙДЕН) ==="
        echo ""
    fi
done