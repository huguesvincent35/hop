;*=====================================================================*/
;*    serrano/prgm/project/hop/1.9.x/src/oto-scheduler.scm             */
;*    -------------------------------------------------------------    */
;*    Author      :  Manuel Serrano                                    */
;*    Creation    :  Tue Feb 26 06:41:38 2008                          */
;*    Last change :  Wed Feb 27 07:46:38 2008 (serrano)                */
;*    Copyright   :  2008 Manuel Serrano                               */
;*    -------------------------------------------------------------    */
;*    One to one scheduler                                             */
;*    -------------------------------------------------------------    */
;*    The characteristics of this scheduler are:                       */
;*      - each request is handled by a new single thread.              */
;*      - on heavy load the new request waits for an old request to    */
;*        complete.                                                    */
;*    This is the simplest and most naive multi-threaded scheduler.    */
;*=====================================================================*/

;*---------------------------------------------------------------------*/
;*    The module                                                       */
;*---------------------------------------------------------------------*/
(module hop_scheduler-one-to-one

   (cond-expand
      (enable-threads
       (library pthread)))

   (library hop)
   
   (import  hop_scheduler
	    hop_param)

   (export  (class one-to-one-scheduler::scheduler
	       (mutex::mutex read-only (default (make-mutex)))
	       (condv::condvar read-only (default (make-condition-variable)))
	       (cur::int (default 0)))))

;*---------------------------------------------------------------------*/
;*    scheduler-stat ::one-to-one-scheduler ...                        */
;*---------------------------------------------------------------------*/
(define-method (scheduler-stat scd::one-to-one-scheduler)
   (with-access::one-to-one-scheduler scd (size cur)
      (format " (~a/~a)" cur size)))

;*---------------------------------------------------------------------*/
;*    scheduler-load ::one-to-one-scheduler ...                        */
;*---------------------------------------------------------------------*/
(define-method (scheduler-load scd::one-to-one-scheduler)
   (with-access::one-to-one-scheduler scd (cur size)
      (flonum->fixnum
       (*fl 100. (/fl (fixnum->flonum cur) (fixnum->flonum size))))))

;*---------------------------------------------------------------------*/
;*    schedule-start ::one-to-one-scheduler ...                        */
;*---------------------------------------------------------------------*/
(define-method (schedule-start scd::one-to-one-scheduler proc msg)
   (with-access::one-to-one-scheduler scd (mutex condv cur size)
      (mutex-lock! mutex)
      (let loop ()
	 (when (>=fx cur size)
	    ;; we have to wait for a thread to complete
	    (condition-variable-wait! condv mutex)
	    (loop)))
      (letrec ((thread (instantiate::hopthread
			  (body (lambda ()
				   (with-handler
				      scheduler-default-handler
				      (proc scd thread))
				   (mutex-lock! mutex)
				   (set! cur (-fx cur 1))
				   (condition-variable-signal! condv)
				   (mutex-unlock! mutex))))))
	 (set! cur (+fx cur 1))
	 (mutex-unlock! mutex)
	 (thread-start! thread))))

;*---------------------------------------------------------------------*/
;*    schedule ::one-to-one-scheduler ...                              */
;*---------------------------------------------------------------------*/
(define-method (schedule scd::one-to-one-scheduler proc msg)
   (proc scd (current-thread)))


