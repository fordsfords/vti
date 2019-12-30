#!/bin/sh
# vti.sh

CUR=`cat vti.cur`
SAV=`cat vti.sav`

perl -e "print 'chk.sh: CUR=' . $CUR . ', SAV=' . $SAV . ', ' . (($CUR - $SAV)/$SAV) . \"\n\";"
