#! /usr/bin/env zsh

yabai -m query --windows --window | jq -re '.id'
