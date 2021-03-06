/*=====================================================================*/
/*    serrano/prgm/project/hop/3.0.x/test/hopjs/noserv/es6-sym.js      */
/*    -------------------------------------------------------------    */
/*    Author      :  Manuel Serrano                                    */
/*    Creation    :  Wed Aug 12 08:24:17 2015                          */
/*    Last change :  Wed Aug 12 09:16:54 2015 (serrano)                */
/*    Copyright   :  2015 Manuel Serrano                               */
/*    -------------------------------------------------------------    */
/*    Testing ES6 symbol support.                                      */
/*      http://www.ecma-international.org/ecma-262/6.0/#19.4           */
/*=====================================================================*/
var assert = require( "assert" );

assert.strictEqual( typeof( Symbol( "foo" ) ), "symbol" );
assert.ok( Symbol( "foo" ) !== Symbol( "foo" ) );
assert.strictEqual( Symbol( "foo" ).toString(), "Symbol(foo)" );
assert.ok( JSON.stringify( Symbol( "foo" ) == "undefined" ) );

assert.throws( function() { new Symbol( "foo" ) } );

var s = Symbol.for( "bar" );

assert.ok( s !== Symbol( "bar" ) );

var s2 = Symbol.for( "bar" );
assert.ok( s === s2 );

assert.ok( Symbol.keyFor( s2 ) );
assert.ok( !Symbol.keyFor( Symbol( "foo" ) ) );

assert.equal( typeof( Symbol.unscopables ), "symbol" );
assert.equal( typeof( Symbol.toPrimitive ), "symbol" );
assert.equal( typeof( Symbol.iterator ), "symbol" );
assert.equal( Symbol.keyFor( Symbol.iterator ), undefined );

assert.throws( function() { new Symbol( "foo" ) + 0; } );
