#!/bin/sh
#*=====================================================================*/
#*    serrano/prgm/project/hop/linux/maemo/makedeb.sh                  */
#*    -------------------------------------------------------------    */
#*    Author      :  Manuel Serrano                                    */
#*    Creation    :  Sat Dec 22 05:37:50 2007                          */
#*    Last change :  Wed May 11 17:10:22 2011 (serrano)                */
#*    Copyright   :  2007-11 Manuel Serrano                            */
#*    -------------------------------------------------------------    */
#*    The Shell script to build the .deb for Hop on Maemo              */
#*    -------------------------------------------------------------    */
#*    Debug with "sh -x makedeb.sh"                                    */
#*=====================================================================*/

#*---------------------------------------------------------------------*/
#*    Global configuration                                             */
#*---------------------------------------------------------------------*/
REPOSITORY=/users/serrano/prgm/distrib
VERSION=2.2.1
BIGLOOVERSION=3.6b
ICONS="hop-16x16.png hop-26x26.png hop-40x40.png hop-64x64.png"
AUTHOR=Manuel.Serrano@inria.fr
LICENSE=gpl
TMP=`pwd`/build.hop
BASEDIR=`dirname $0`
HOPPREFIX=/opt/bigloo
PREFIX=/usr

if [ "$REPODIR " != " " ]; then
  REPOSITORY=$REPODIR;
fi

#*---------------------------------------------------------------------*/
#*    Create the TMP directories                                       */
#*---------------------------------------------------------------------*/
/bin/rm -rf $TMP
mkdir -p $TMP

#*---------------------------------------------------------------------*/
#*    Untar the standard Hop version                                   */
#*---------------------------------------------------------------------*/
tar xfz $REPOSITORY/hop-$VERSION.tar.gz -C $TMP

#*---------------------------------------------------------------------*/
#*    The maemo configuration                                          */
#*---------------------------------------------------------------------*/
maemo=`pkg-config maemo-version --modversion` 2> /dev/null

if [ $? = 0 ]; then
  debian=maemo
  extradepend="hildon-desktop, "
else
  debian=debian
  extradepend=
fi

#*---------------------------------------------------------------------*/
#*    Install the maemo specific files (including hop-launcher)        */
#*---------------------------------------------------------------------*/
if [ "$debian " = "maemo " ]; then
  mkdir -p $TMP/hop-$VERSION/maemo
  (cd $BASEDIR/hop-launcher && make clean)
  (cp -r $BASEDIR/hop-launcher $TMP/hop-$VERSION/maemo)
  (cd $TMP/hop-$VERSION/maemo/hop-launcher && \
   branch=`echo $VERSION | sed -e "s/[0-9]*$/x/g"` && \
   cat configure.in | sed -e "s/@HOPBRANCH@/$branch/g" > configure && \
   cat hop-launcher.rc.in | \
      sed -e "s|@HOPPREFIX@|$HOPPREFIX|g" | \
      sed -e "s|@PREFIX@|$PREFIX|g" > hop-launcher.rc && \
   ./configure)

  mkdir -p $TMP/hop-$VERSION/icons
  for p in $ICONS; do 
    cp $BASEDIR/$p $TMP/hop-$VERSION/icons;
  done
fi

#*---------------------------------------------------------------------*/
#*    Configure for small devices                                      */
#*---------------------------------------------------------------------*/
cat >> $TMP/hop-$VERSION/etc/hoprc.hop.in <<EOF
;; small device configuration
(hop-max-threads-set! 8)
EOF

#*---------------------------------------------------------------------*/
#*    Create the .tar.gz file used for building the package            */
#*---------------------------------------------------------------------*/
tar cfz $TMP/hop-$VERSION.tar.gz -C $TMP hop-$VERSION

if [ "$debian " = "maemo " ]; then
  cat $BASEDIR/Makefile.maemo | \
    sed -e "s/@HOPBRANCH@/$branch/g" | \
    sed -e "s|@HOPPREXI@|$HOPREFIX|g" | \
    sed -e "s|@PREFIX@|$PREFIX|g" >> \
    $TMP/hop-$VERSION/Makefile

  echo 'BUILDSPECIFIC=build-maemo' >> \
    $TMP/hop-$VERSION/etc/Makefile.hopconfig.in
    echo 'INSTALLSPECIFIC=install-maemo' >> \
    $TMP/hop-$VERSION/etc/Makefile.hopconfig.in
fi

#*---------------------------------------------------------------------*/
#*    The maemo version                                                */
#*---------------------------------------------------------------------*/
if [ "$debian " = "maemo " ]; then
  if [ "$maemo " = "5.0 " ]; then
    echo "Configuring for Maemo 5."
    childonflags="pkg-config gtk+-2.0 hildon-1 --cflags"
    ldhildonflags="pkg-config gtk+-2.0 hildon-1 --libs"
    maemo=MAEMO5
    maemohaslocation=no
  else
    pkg-config gtk+-2.0 hildon-1 --cflags > /dev/null 2> /dev/null
    if [ $? = 0 ]; then
      echo "Configuring for Maemo 4."
      childonflags="pkg-config gtk+-2.0 hildon-1 --cflags"
      ldhildonflags="pkg-config gtk+-2.0 hildon-1 --libs"
      maemo=MAEMO4
      maemohaslocation=yes
    else
      echo "Configuring for Maemo 3."
      childonflags="pkg-config gtk+-2.0 hildon-libs --cflags"
      ldhildonflags="pkg-config gtk+-2.0 hildon-libs --libs"
      maemo=MAEMO3
      maemohaslocation=yes
    fi
  fi
fi

#*---------------------------------------------------------------------*/
#*    Start creating the .deb                                          */
#*---------------------------------------------------------------------*/
(cd $TMP/hop-$VERSION &&
 dh_make -c $LICENSE -s -e $AUTHOR -f ../hop-$VERSION.tar.gz <<EOF

EOF
)

# debian specific
for p in control rules postinst postrm; do
  if [ -f $BASEDIR/debian/$p.in ]; then
    cat $BASEDIR/debian/$p.in \
      | sed -e "s/@HOPVERSION@/$VERSION/g" \
            -e "s/@MAEMO@/$maemo/g" \
            -e "s/@DEBIAN@/$debian/g" \
            -e "s/@EXTRADEPEND@/$extradepend/g" \
            -e "s|@HOPPREFIX@|$HOPPREFIX|g" \
            -e "s|@PREFIX@|$PREFIX|g" \
            -e "s/@MAEMOHASLOCATION@/$maemohaslocation/g" \
            -e "s/@BIGLOOVERSION@/$BIGLOOVERSION/g" > \
      $TMP/hop-$VERSION/debian/$p;
  else
    cp $BASEDIR/debian/$p $TMP/hop-$VERSION/debian;
  fi
done

# The desktop file
cp $TMP/hop-$VERSION/LICENSE $TMP/hop-$VERSION/copyright
cat $BASEDIR/hop.desktop.in \
  | sed -e "s/@HOPVERSION@/$VERSION/g" \
        -e "s|@HOPPREFIX@|$HOPPREFIX|g" \
        -e "s|@PREFIX@|$PREFIX|g" > \
  $TMP/hop-$VERSION/maemo/hop.desktop && \
  chmod a-w $TMP/hop-$VERSION/maemo/hop.desktop
cat > $TMP/hop-$VERSION/debian/hop.links <<EOF
$PREFIX/share/applications/hildon/hop.desktop etc/others-menu/extra_applications/hop.desktop
EOF

# The service
cat $BASEDIR/hop.service.in  \
  | sed -e "s/@HOPVERSION@/$VERSION/g" \
        -e "s|@HOPPREFIX@|$HOPPREFIX|g" \
        -e "s|@PREFIX@|$PREFIX|g" > \
  $TMP/hop-$VERSION/maemo/hop.service

# The changelog file
/bin/rm -f $TMP/hop-$VERSION/debian/changelog
cat $TMP/hop-$VERSION/ChangeLog | grep -v "^[ \\t]*[.]$$" > \
   $TMP/hop-$VERSION/debian/changelog
cat $BASEDIR/debian/changelog.in | sed "s/@HOPVERSION@/$VERSION/g" > \
   $TMP/hop-$VERSION/debian/changelog

(cd $TMP/hop-$VERSION && dpkg-buildpackage -rfakeroot)

#*---------------------------------------------------------------------*/
#*    Cleanup tmp files                                                */
#*---------------------------------------------------------------------*/
/bin/rm -f $TMP/hop-$VERSION.tar.gz
/bin/rm -f $TMP/hop_$VERSION.tar.gz
/bin/rm -f $TMP/hop_$VERSION.orig.tar.gz

#*---------------------------------------------------------------------*/
#*    Copy the deb file                                                */
#*---------------------------------------------------------------------*/
maemo=`pkg-config maemo-version --modversion`

if [ $? = 0 ]; then
  debian=maemo`echo $maemo | sed -e "s/[.].*$//"`
else
  debian=debian
fi

cp $TMP/hop_"$VERSION"_armel.deb $REPOSITORY/$debian