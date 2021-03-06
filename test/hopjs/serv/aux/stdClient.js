/*=====================================================================*/
/*    serrano/prgm/project/hop/3.0.x/test/hopjs/serv/aux/stdClient.js  */
/*    -------------------------------------------------------------    */
/*    Author      :  Vincent Prunet                                    */
/*    Creation    :  Tue Sep  15 11:43:00 2015                         */
/*    Last change :  Tue Sep  15 12:42:26 2015 (serrano)               */
/*    Copyright   :  2015 Inria                                        */
/*    -------------------------------------------------------------    */
/*    simple worker to stress test services                            */
/*=====================================================================*/

/* This worker iterates <num> service invocations, then
 * post a message to inform the main thread of completion */

import service toTest();


function test( id, num ) {
   if ( num == 0 ) {
      postMessage( { messageType: 'done' });
   } else {
      console.log( 'client #%s: call #%s', id, num );
      try {
	 toTest( id, num ).post( function( result ) {
	    test( id, num - 1 );
	 }, { fail: function( error ) {
	    console.log( 'Service invocation failed for client #%s, #%s',
			 id, num );
	    postMessage( { messageType: 'failure' } );
	 }});
      }
      catch( e ) {
	 console.log( 'client %s cannot post at %s', id, num );
	 postMessage( { messageType: 'failure' } );
      }
   };
}


/* Protocol with workers launcher */
onmessage = function( e ) {
   switch (e.data.messageType) {
   case 'params':
      id = e.data.clientId;
      num = e.data.num;
      postMessage( { messageType: 'ready' } );
      break;
   case 'run':
      test( id, num );
   }
};
