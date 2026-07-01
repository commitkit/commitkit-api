#!/bin/bash

# Get Trello Token
# This script opens the Trello authorization page in your browser

API_KEY="14f002cf6a5c9f98ca13d60e9b787fc9"

echo "🔑 Getting Trello Token..."
echo ""
echo "Opening browser to authorize the application..."
echo ""
echo "Click 'Allow' to generate your token"
echo ""

# Construct authorization URL
AUTH_URL="https://trello.com/1/authorize?expiration=never&name=CommitKit+CLI+Board+Creator&scope=read,write&response_type=token&key=${API_KEY}"

# Open in browser (works on macOS, Linux, WSL)
if command -v open &> /dev/null; then
    open "$AUTH_URL"
elif command -v xdg-open &> /dev/null; then
    xdg-open "$AUTH_URL"
else
    echo "Please open this URL in your browser:"
    echo "$AUTH_URL"
fi

echo ""
echo "After authorizing, copy the token and run:"
echo "  export TRELLO_API_KEY=\"14f002cf6a5c9f98ca13d60e9b787fc9\""
echo "  export TRELLO_TOKEN=\"<paste-your-token-here>\""
echo "  node scripts/create-trello-board.js"
