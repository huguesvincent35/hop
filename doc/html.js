/*=====================================================================*/
/*    serrano/prgm/project/hop/3.0.x/doc/html40.js                     */
/*    -------------------------------------------------------------    */
/*    Author      :  Manuel Serrano                                    */
/*    Creation    :  Mon Oct 26 11:41:07 2015                          */
/*    Last change :  Mon Oct 26 16:44:06 2015 (serrano)                */
/*    Copyright   :  2015 Manuel Serrano                               */
/*    -------------------------------------------------------------    */
/*    Parses the HTML4.01 documentation for generating the index.      */
/*=====================================================================*/
"use hopscript";

/*---------------------------------------------------------------------*/
/*    import                                                           */
/*---------------------------------------------------------------------*/
var path = require( "path" );

/*---------------------------------------------------------------------*/
/*    chapterTitle ...                                                 */
/*---------------------------------------------------------------------*/
var chapterTitle = "html";

/*---------------------------------------------------------------------*/
/*    compileHTML40Index ...                                           */
/*---------------------------------------------------------------------*/
function compileHTML40Index( file ) {
   var ast = require( file, "html" );
   var entries = [];
   var base = path.dirname( file );

   // find all the As child of TD
   var tds = ast.getElementsByTagName( "td" )
       .filter( function( el, idx=undefined, arr=undefined ) {
	  if( el.title == "Name" ) {
	     if( el.childNodes[ 0 ].tagName === "a" ) {
		// got one
		var href = el.childNodes[ 0 ].href;
		var key = el.childNodes[ 0 ].childNodes[ 0 ]
		    .toString()
		    .replace( /\n/g, '' );
		var o = { key: key.toLowerCase(),
			  proto: "&lt;" + key + " [attributes]&gt;",
			  chapter: chapterTitle,
			  url: path.join( base, href )
			};

		entries.push( o );
	     }
	  }
       } );

   console.log( JSON.stringify( entries ) );
}

compileHTML40Index( process.argv[ 2 ] );