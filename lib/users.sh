#!/usr/bin/env bash

user_add() {
    local email="${1:-}" uuid="${2:-}"
    [ -n "$email" ] || die "Usage: ./xrayctl.sh user add email [uuid]"
    validate_email "$email" || die "Invalid email: $email"

    init_state_files
    if jq -e --arg email "$email" '.users[]? | select(.email == $email)' "$USERS_FILE" >/dev/null; then
        die "User already exists: $email"
    fi

    if [ -z "$uuid" ]; then
        uuid="$(generate_uuid)"
    else
        uuid="$(generate_uuid "$uuid")"
    fi
    validate_uuid "$uuid" || die "Invalid UUID: $uuid"
    if jq -e --arg uuid "${uuid,,}" '.users[]? | select((.id | ascii_downcase) == $uuid)' "$USERS_FILE" >/dev/null; then
        die "UUID is already assigned to another user: $uuid"
    fi

    jq --arg email "$email" --arg uuid "$uuid" \
        '.users += [{"email": $email, "id": $uuid, "level": 0}]' \
        "$USERS_FILE" > "$USERS_FILE.tmp"
    replace_private_file "$USERS_FILE.tmp" "$USERS_FILE"
    ok "Added user $email"
    printf 'UUID: %s\n' "$uuid"
}

user_delete() {
    local email="${1:-}"
    [ -n "$email" ] || die "Usage: ./xrayctl.sh user del email"
    init_state_files
    if ! jq -e --arg email "$email" '.users[]? | select(.email == $email)' "$USERS_FILE" >/dev/null; then
        die "User not found: $email"
    fi
    jq --arg email "$email" '.users |= map(select(.email != $email))' \
        "$USERS_FILE" > "$USERS_FILE.tmp"
    replace_private_file "$USERS_FILE.tmp" "$USERS_FILE"
    ok "Deleted user $email"
}

user_add_and_apply() {
    local email="${1:-}" uuid="${2:-}"
    transaction_begin
    user_add "$email" "$uuid"
    apply_xray_config_and_restart
    transaction_commit
}

user_delete_and_apply() {
    local email="${1:-}"
    transaction_begin
    user_delete "$email"
    apply_xray_config_and_restart
    transaction_commit
}

user_list() {
    init_state_files
    local count
    count="$(jq '.users | length' "$USERS_FILE")"
    if [ "$count" -eq 0 ]; then
        printf 'No users configured.\n'
        return 0
    fi
    jq -r '.users[] | [.email, .id, (.level // 0)] | @tsv' "$USERS_FILE" |
        awk 'BEGIN { printf "%-32s %-38s %s\n", "EMAIL", "UUID", "LEVEL" }
             { printf "%-32s %-38s %s\n", $1, $2, $3 }'
}

user_uuid_by_email() {
    local email="$1"
    init_state_files
    jq -r --arg email "$email" '.users[]? | select(.email == $email) | .id' "$USERS_FILE"
}

single_user_email() {
    init_state_files
    jq -r 'if (.users | length) == 1 then .users[0].email else empty end' "$USERS_FILE"
}
