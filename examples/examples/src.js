/*=====================================================================*/
/*    serrano/prgm/project/hop/3.0.x/examples/examples/src.js          */
/*    -------------------------------------------------------------    */
/*    Author      :  Manuel Serrano                                    */
/*    Creation    :  Fri Dec 19 10:32:06 2014                          */
/*    Last change :  Thu Jan  7 07:58:17 2016 (serrano)                */
/*    Copyright   :  2014-16 Manuel Serrano                            */
/*    -------------------------------------------------------------    */
/*    Read and fontify the examples source codes.                      */
/*    -------------------------------------------------------------    */
/*    run: hop -v -g examples.js                                       */
/*    browser: http://localhost:8080/hop/examples                      */
/*=====================================================================*/
var fs = require( "fs" );
var fontifier = require( hop.fontifier );

/*---------------------------------------------------------------------*/
/*    examplesSrc ...                                                  */
/*---------------------------------------------------------------------*/
service examplesSrc( path ) {
   return new Promise( function( resolve, reject ) {
      var fontify = fontifier.hopscript;
      var lbegin = 14;
      
      if( path.match( /[.]hss$/ ) ) {
	 fontify = fontifier.hss;
	 lbegin = 11;
      } else if( path.match( /[.]json$/ ) ) {
	 fontify = fontifier.javascript;
	 lbegin = 1;
      } else if( path.match( /[.]html$/ ) ) {
	 lbegin = 0;
	 fontify = fontifier.xml;
      } else if( path.match( /[.]hop$/ ) ) {
	 fontify = fontifier.hop;
	 lbegin = 1;
      }

      fs.readFile( path, function( err, buf ) {
	 resolve( <pre class="fontifier-prog">${fontifier.lineNumber( fontify( buf, lbegin ) )}</pre> )
      } );
   } );
}

