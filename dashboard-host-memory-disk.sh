#!/bin/bash

# leonstrand@gmail.com


free -g
echo
df -hl | awk '$NF ~ /on|^\/$|elk/'
