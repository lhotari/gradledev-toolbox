#!/bin/bash
file="$1"
if [ -z "$file" ]; then
   echo "usage: $0 file.xml"
   exit 1
fi
command -v xsltproc >/dev/null 2>&1 || {
   echo "xsltproc is required."
   exit 1
}
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
xsltproc "$DIR/junit-xml-format-errors.xsl" "$file"