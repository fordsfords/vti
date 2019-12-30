#!/bin/sh
# vti.sh

cd $HOME/vti

DATE=`date`
if [ "$1" = "" ]; then :
  wget -q -O - https://finance.yahoo.com/quote/VTI >vti.page
  ./vti.pl <vti.page >vti.new
  LINES=`wc -l <vti.new`
  if [ $LINES -ne 1 ]; then :
    echo "VTI ERROR: LINES=$LINES"
    cp vti.page vti.page.err
    exit 1
  fi
  CUR=`cat vti.new`
  if [ "$CUR" -eq 0 ]; then :
    echo "VTI ERROR: CUR=$CUR"
    cp vti.page vti.page.err
    exit 1
  fi
  mv vti.new vti.cur
  echo "$CUR $DATE" >>vti.hist
else :
  echo "$1" >vti.cur
  CUR=`cat vti.cur`
  # Don't accumulate history for tests.
fi

# Should only happen the very first time this is run.
if [ ! -f vti.sav ]; then :
  cp vti.cur vti.sav
fi

SAV=`cat vti.sav`
if [ $CUR -gt $SAV ]; then :
  # new high
  cp vti.cur vti.sav
else :
  perl -e "if ((($CUR - $SAV)/$SAV) < -.009) { print \"VTI $SAV $CUR\n\"; }"
fi
