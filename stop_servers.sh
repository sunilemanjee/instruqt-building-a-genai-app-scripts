#!/bin/bash

echo "Stopping Flask server..."
pkill -f "python -m src.server.flask"

echo "Stopping Yarn dev server..."
pkill -f "yarn run dev"

echo "Checking if processes are still running..."
sleep 2

# Check if Flask is still running
if pgrep -f "python -m src.server.flask" > /dev/null; then
    echo "Flask server is still running"
else
    echo "Flask server stopped successfully"
fi

# Check if Yarn is still running
if pgrep -f "yarn run dev" > /dev/null; then
    echo "Yarn dev server is still running"
else
    echo "Yarn dev server stopped successfully"
fi 