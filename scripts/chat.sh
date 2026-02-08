#!/bin/bash

API_URL="http://llm.local/v1/chat/completions"
MODEL="TinyLlama-1.1B-Chat-v1.0"
MESSAGES='[]'

echo "Chat with ${MODEL} (type 'quit' to exit)"
echo "-------------------------------------------"

while true; do
  printf "\nYou: "
  read -r input
  [ "$input" = "quit" ] && break
  [ -z "$input" ] && continue

  # Append user message to history
  MESSAGES=$(echo "$MESSAGES" | jq --arg msg "$input" '. + [{"role": "user", "content": $msg}]')

  # Call the API
  RESPONSE=$(curl -s "$API_URL" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg model "$MODEL" \
      --argjson messages "$MESSAGES" \
      '{model: $model, messages: $messages, max_tokens: 256}')")

  # Extract reply
  REPLY=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty')

  if [ -z "$REPLY" ]; then
    ERROR=$(echo "$RESPONSE" | jq -r '.error.message // empty')
    echo -e "\n[Error: ${ERROR:-no response from model}]"
    # Remove the failed user message from history
    MESSAGES=$(echo "$MESSAGES" | jq '.[:-1]')
    continue
  fi

  # Append assistant reply to history
  MESSAGES=$(echo "$MESSAGES" | jq --arg msg "$REPLY" '. + [{"role": "assistant", "content": $msg}]')

  echo -e "\nLLM: ${REPLY}"
done
