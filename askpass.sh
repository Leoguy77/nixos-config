#!/bin/bash
# Simple askpass helper that reads password from terminal
exec < /dev/tty
read -s -p "Password: " password
echo "$password"
