;*=====================================================================*/
;*    serrano/prgm/project/hop/3.0.x/js2scheme/token.sch               */
;*    -------------------------------------------------------------    */
;*    Author      :  Manuel Serrano                                    */
;*    Creation    :  Thu Jul 23 18:19:18 2015                          */
;*    Last change :  Wed Jul 29 19:47:24 2015 (serrano)                */
;*    Copyright   :  2015 Manuel Serrano                               */
;*    -------------------------------------------------------------    */
;*    Token tools                                                      */
;*=====================================================================*/

;*---------------------------------------------------------------------*/
;*    the-choord ...                                                   */
;*    -------------------------------------------------------------    */
;*    Builds a Bigloo location object                                  */
;*---------------------------------------------------------------------*/
(define (the-coord input-port offset)
   `(at ,(input-port-name input-port)
       ,(-fx (input-port-position input-port) offset)))

;*---------------------------------------------------------------------*/
;*    make-token ...                                                   */
;*---------------------------------------------------------------------*/
(define (make-token type value loc)
   (econs type value loc))

;*---------------------------------------------------------------------*/
;*    token ...                                                        */
;*---------------------------------------------------------------------*/
(define-macro (token type value offset)
   `(make-token ,type ,value (the-coord (the-port) ,offset)))

;*---------------------------------------------------------------------*/
;*    token-tag ...                                                    */
;*---------------------------------------------------------------------*/
(define (token-tag token)
   (car token))

;*---------------------------------------------------------------------*/
;*    token-tag-set! ...                                               */
;*---------------------------------------------------------------------*/
(define (token-tag-set! token tag)
   (set-car! token tag))

;*---------------------------------------------------------------------*/
;*    token-value ...                                                  */
;*---------------------------------------------------------------------*/
(define (token-value token)
   (cdr token))

;*---------------------------------------------------------------------*/
;*    token-loc ...                                                    */
;*---------------------------------------------------------------------*/
(define (token-loc token)
   (cer token))
