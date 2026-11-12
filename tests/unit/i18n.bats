#!/usr/bin/env bats

load helper

setup() { load_toastbox; }

@test "both languages define the same keys" {
  local en zh
  en="$(printf '%s\n' "${!TB_MSG_EN[@]}" | sort)"
  zh="$(printf '%s\n' "${!TB_MSG_ZH[@]}" | sort)"
  [ "$en" = "$zh" ]
}

@test "translations take the same number of arguments" {
  local key en zh
  for key in "${!TB_MSG_EN[@]}"; do
    en="$(grep -o '%s' <<<"${TB_MSG_EN[$key]}" | wc -l)"
    zh="$(grep -o '%s' <<<"${TB_MSG_ZH[$key]}" | wc -l)"
    if [ "$en" != "$zh" ]; then
      echo "argument count differs for $key: en=$en zh=$zh" >&2
      return 1
    fi
  done
}

@test "every message key used in the code is defined" {
  local key missing=0
  # First argument of msg / log_* / die / ask / confirm / kv, wherever a
  # bare lower_snake key is used.
  while IFS= read -r key; do
    if [[ -z "${TB_MSG_EN[$key]+x}" ]]; then
      echo "undefined message key: $key" >&2
      missing=1
    fi
  done < <(
    grep -ohE '\b(msg|log_info|log_ok|log_warn|log_err|die|kv) "?[a-z]+_[a-z0-9_]+' "$REPO_ROOT"/src/lib/*.sh |
      awk '{print $2}' | tr -d '"' | sort -u
    grep -ohE '\b(confirm [yn]|ask "[^"]*"|ask_valid [A-Za-z_]+ "[^"]*" [a-z_]+) [a-z]+_[a-z0-9_]+' "$REPO_ROOT"/src/lib/*.sh |
      awk '{print $NF}' | sort -u
  )
  [ "$missing" -eq 0 ]
}

@test "every defined key is used somewhere" {
  local key unused=0
  for key in "${!TB_MSG_EN[@]}"; do
    if ! grep -qE "(^|[^A-Za-z_\[])$key([^A-Za-z0-9_]|\$)" "$REPO_ROOT"/src/lib/[2-9]*.sh "$REPO_ROOT"/src/lib/00-core.sh; then
      echo "unused message key: $key" >&2
      unused=1
    fi
  done
  [ "$unused" -eq 0 ]
}

@test "msg falls back to English, then to the key" {
  TB_LANG="zh"
  TB_MSG_EN[only_en]="english %s"
  [ "$(msg only_en x)" = "english x" ]
  [ "$(msg no_such_key)" = "no_such_key" ]
  [ "$(msg err_core 测试)" = "未知内核“测试”，可选 xray 或 sing-box。" ]
}
