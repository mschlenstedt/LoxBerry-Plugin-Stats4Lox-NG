#!/bin/bash
lang=$i
name=$2

curl -sL --cookie "loxone_langswitch=$1$1,$1$1" https://www.loxone.com/help/$2 | grep "content=\"0;URL=" | cut -d'=' -f4 | cut -d'"' -f1 | rev | cut -d'/' -f2 | rev

