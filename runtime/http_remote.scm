;*=====================================================================*/
;*    serrano/prgm/project/hop/2.2.x/runtime/http_remote.scm           */
;*    -------------------------------------------------------------    */
;*    Author      :  Manuel Serrano                                    */
;*    Creation    :  Sun Jul 23 15:46:32 2006                          */
;*    Last change :  Fri Jul  9 10:21:31 2010 (serrano)                */
;*    Copyright   :  2006-10 Manuel Serrano                            */
;*    -------------------------------------------------------------    */
;*    The HTTP remote response                                         */
;*=====================================================================*/

;*---------------------------------------------------------------------*/
;*    The module                                                       */
;*---------------------------------------------------------------------*/
(module __hop_http-remote

   (include "http-lib.sch")

   (library web)
   
   (import  __hop_param
	    __hop_types
	    __hop_misc
	    __hop_http-lib
	    __hop_http-response
	    __hop_user
	    __hop_http-error)

   (static  (class connection
	       (id::long read-only)
	       (socket::socket read-only)
	       (key::bstring read-only)
	       (host::bstring read-only)
	       (port::int read-only)
	       request-id::obj
	       (keep-alive::bool (default #f))
	       (intable::bool (default #f))
	       (%%debug-closed::bool (default #f))
	       (locked::bool (default #f))
	       (wstart?::bool (default #f))
	       date::elong))
   
   (export  (response-remote-start-line ::http-response-remote)))

;*---------------------------------------------------------------------*/
;*    response-remote-start-line ...                                   */
;*---------------------------------------------------------------------*/
(define (response-remote-start-line resp)	    
   (with-access::http-response-remote resp (scheme host port path http method userinfo)
      (let ((p (if (string? userinfo)
		   (string-append userinfo "@" path)
		   path)))
	 (cond
	    ((not (hop-use-proxy))
	     (format "~a ~a ~a" method p http))
	    ((not hostname)
	     (format "~a ~a://~a ~a" method scheme p http))
	    ((not port)
	     (format "~a ~a://~a~a ~a" method scheme host p http))
	    (else
	     (format "~a ~a://~a:~a~a ~a" method scheme host port p http))))))

;*---------------------------------------------------------------------*/
;*    http-response ::http-response-remote ...                         */
;*---------------------------------------------------------------------*/
(define-method (http-response r::http-response-remote socket)
   (with-trace 3 'http-response::http-response-remote
      (let loop ()
	 (with-access::http-response-remote r (scheme host port header content-length remote-timeout request connection-timeout)
	    (trace-item "remotehost=" host
			" remoteport=" port
			" connection-timeout=" connection-timeout)
	    (let* ((host (or (hop-use-proxy-host) host))
		   (port (or (hop-use-proxy-port) port))
		   (ssl (eq? scheme 'https))
		   (remote #f))
	       (with-handler
		  (lambda (e)
		     (unless (&io-error? e) (error-notify e))
		     (when remote
			(with-trace 4 'connection-close@handler
			   (connection-close! remote)))
		     (cond
			((&io-unknown-host-error? e)
			 (http-response (http-error e) socket))
			((not remote)
			 (raise e))
			((connection-wstart? remote)
			 ;; If we have already sent characters to the client
			 ;; it is no longer possible to repl with "resource
			 ;; unavailable" so we raise the error.
			 (raise e))
			((connection-keep-alive remote)
			 ;; This is a keep-alive connection that is likely
			 ;; to have been closed by the remote server, we
			 ;; retry with a fresh connection
			 (hop-verb 3
				   (hop-color request request " RESET.ka")
				   " (alive since "
				   (connection-request-id remote)
				   ") " host ":" port "\n")
			 (http-response r socket))
			(else
			 ;; This is an unrecoverable error
			 (http-response (http-remote-error host e) socket))))
		  (begin
		     (set! remote (remote-get-socket host port connection-timeout request ssl))
		     ;; verb
		     (if (connection-keep-alive remote)
			 (hop-verb 3
				   (hop-color request request " REMOTE.ka")
				   " (alive since "
				   (connection-request-id remote)
				   ") " host ":" port "\n")
			 (hop-verb 3
				   (hop-color request request " REMOTE")
				   " " host ":" port "\n"))
		     (let ((rp (connection-output remote))
			   (sp (socket-input socket)))
			(when (>fx remote-timeout 0)
			   (output-timeout-set! rp remote-timeout)
			   (input-timeout-set! (connection-input remote) remote-timeout))
			;; the header and the request
			(with-trace 4 'http-response-header
			   (trace-item "start-line: "
				       (response-remote-start-line r))
			   (remote-header header rp r)
			   ;; if a char is ready and is eof, it means that the
			   ;; connection is closed
			   (if (connection-down? remote)
			       (begin
				  (with-trace 4 "connection-close@down"
				     (trace-item "remote=" remote)
				     (connection-close! remote))
				  (loop))
			       (begin
				  ;; the content of the request
				  (when (>elong content-length #e0)
				     (trace-item "send-chars.1 cl=" content-length)
				     (send-chars sp rp content-length))
				  (flush-output-port rp)
				  ;; capture dumping
				  (when (output-port? (hop-capture-port))
				     (log-capture request r))
				  (if (assq :xhr-multipart header)
				      (remote-multipart-body r socket remote)
				      (remote-body r socket remote)))))))))))))

;*---------------------------------------------------------------------*/
;*    log-capture ...                                                  */
;*---------------------------------------------------------------------*/
(define (log-capture request r)
   (let ((cp (hop-capture-port)))
      (display "---------------------------------------------------------\n" cp)
      (fprintf cp "http://~a:~a~a\n\n"
	       (http-request-host request)
	       (http-request-port request)
	       (http-request-path request))
      (remote-header (http-response-remote-header r) cp r)
      (flush-output-port cp)))

;*---------------------------------------------------------------------*/
;*    remote-header ...                                                */
;*---------------------------------------------------------------------*/
(define (remote-header header::pair-nil rp::output-port r::http-response-remote)
   (http-write-line rp (response-remote-start-line r))
   (http-write-header rp (http-filter-proxy-header header))
   (when (hop-enable-remote-keep-alive)
      (let ((h (if (hop-use-proxy-host)
		   "proxy-connection: keep-alive"
		   "connection: keep-alive")))
	 (http-write-line rp h)))
   (http-write-line rp))

;*---------------------------------------------------------------------*/
;*    remote-multipart-body ...                                        */
;*    -------------------------------------------------------------    */
;*    Same thing as remote-body but timeouts must be disabled and      */
;*    errors ignored (which do not make sense because multipart        */
;*    is used for long polling).                                       */
;*    timeout does not make sense).                                    */
;*---------------------------------------------------------------------*/
(define (remote-multipart-body r socket remote)
   (with-handler
      (lambda (e) 'close)
      (input-timeout-set! (connection-input remote) 0)
      (remote-body r socket remote)))

;*---------------------------------------------------------------------*/
;*    remote-body ...                                                  */
;*---------------------------------------------------------------------*/
(define (remote-body r::http-response-remote socket remote::connection)
   (with-access::http-response-remote r (host port timeout request)
      ;; the body
      (with-trace 4 'http-response-body
	 (let* ((wstart #f)
		(ip (connection-input remote))
		(op (socket-output socket)))
	    (when (>fx timeout 0)
	       (output-timeout-set! op timeout))
	    (multiple-value-bind (http-version status-code phrase)
	       (http-parse-status-line ip)
	       ;; CAR MS: TO BE REMOVED
	       (unless (integer? status-code)
		  (error 'remote-body "status-code not a integer" status-code))
	       (multiple-value-bind (header _1 _2 cl te _3 _4 connection)
		  (http-parse-header ip (connection-output remote))
		  ;; WARNING: phrase contains its terminal \r\n hence
		  ;; it must be displayed with regular scheme writer,
		  ;; not HTTP-WRITE-LINE!
		  (trace-item "# " http-version " " status-code " "
			      (string-for-read phrase))
		  (trace-item "content-length=" cl)
		  (trace-item "transfer-encoding=" te)
		  (display http-version op)
		  (display " " op)
		  (display status-code op)
		  (display " " op)
		  (display phrase op)
		  (http-write-header op header)
		  (http-write-line op)
		  (case status-code
		     ((204 304)
		      ;; no message body
		      #unspecified)
		     (else
		      (let ((snif (and (hop-enable-proxy-sniffer)
				       ((hop-proxy-sniffer) request))))
			 (if (output-port? snif)
			     (let ((op2 (if (output-port? snif)
					    (open-output-procedure
					     (lambda (s)
						(display s snif)
						(display s op))
					     (lambda ()
						(flush-output-port snif)
						(flush-output-port op)))
					    op)))
				(with-trace 4 'http-snif
				   (trace-item "request=" request))
				(unwind-protect
				   (if (eq? te 'chunked)
				       (let ((trailers (assq 'te header)))
					  (when trailers
					     (print "******* te=" trailers))
					  (http-send-chunks ip op2 #f))
				       (unless (=elong cl #e0)
					  (send-chars ip op2 cl)))
				   (begin
				      (flush-output-port snif)
				      (flush-output-port op2)
				      (close-output-port snif)
				      (close-output-port op2))))
			     (if (eq? te 'chunked)
				 (let ((trailers (assq 'te header)))
				    (when trailers
				       (print "******* te=" trailers))
				    (http-send-chunks ip op #f))
				 (unless (=elong cl #e0)
				    (send-chars ip op cl)))))))
		  (flush-output-port op)
		  ;; what to do with the remote connection. if the
		  ;; status code is not 200, we always close the connection
		  ;; in order to avoid, in particular, re-direct problems.
		  (if (or (>=fx status-code 500)
			  (eq? connection 'close)
			  (and (not connection)
			       (string=? http-version "HTTP/1.0"))
			  (not (hop-enable-remote-keep-alive)))
		      (with-trace 4 'connection-close@remote-body
			 (trace-item "remote=" remote)
			 (connection-close! remote))
		      (connection-keep-alive! remote))
		  ;; return to the main hop loop
		  (let ((s (http-header-field
			    (http-request-header request)
			    proxy-connection:)))
		     (if (and (or (>elong cl #e0) (eq? te 'chunked))
			      (string? s))
			 (string->symbol s)
			 'close))))))))

;*---------------------------------------------------------------------*/
;*    *remote-lock* ...                                                */
;*---------------------------------------------------------------------*/
(define *remote-lock* (make-mutex "remote"))

;*---------------------------------------------------------------------*/
;*    *connection-table* ...                                           */
;*---------------------------------------------------------------------*/
(define *connection-table* (make-hashtable))
(define *open-connection-number* 0)
(define *keep-alive-connection-number* 0)
(define *connection-id* 0)

;*---------------------------------------------------------------------*/
;*    ++ ...                                                           */
;*---------------------------------------------------------------------*/
(define-macro (++ v)
   `(set! ,v (+fx ,v 1)))

;*---------------------------------------------------------------------*/
;*    -- ...                                                           */
;*---------------------------------------------------------------------*/
(define-macro (-- v)
   `(set! ,v (-fx ,v 1)))

;*---------------------------------------------------------------------*/
;*    connection-table-get ...                                         */
;*    -------------------------------------------------------------    */
;*    This function assumes that *remote-lock* is acquired.            */
;*---------------------------------------------------------------------*/
(define (connection-table-get key)
   (let ((lst (hashtable-get *connection-table* key)))
      (when (pair? lst)
	 (let ((cs (current-seconds)))
	    (let loop ((lst lst))
	       (cond
		  ((null? lst)
		   #f)
		  ((connection-locked (car lst))
		   (loop (cdr lst)))
		  ((connection-timeout? (car lst) cs)
		   (connection-close-sans-lock! (car lst))
		   (loop (cdr lst)))
		  (else
		   (with-access::connection (car lst) (locked wstart? date)
		      (set! date cs)
		      (set! locked #t)
		      (set! wstart? #f)
		      (car lst)))))))))

;*---------------------------------------------------------------------*/
;*    connection-table-put! ...                                        */
;*---------------------------------------------------------------------*/
(define (connection-table-put! host port conn)
   (hashtable-update! *connection-table*
		      (string-append host ":" port)
		      (lambda (v)
			 (cons conn v))
		      (list conn)))

;*---------------------------------------------------------------------*/
;*    close-connection! ...                                            */
;*    -------------------------------------------------------------    */
;*    This function assumes *remote-lock* acquired.                    */
;*---------------------------------------------------------------------*/
(define (close-connection! conn)
   (with-access::connection conn (socket %%debug-closed)
      (-- *open-connection-number*)
      (set! %%debug-closed #t)
      (socket-close socket)))

;*---------------------------------------------------------------------*/
;*    connection-timeout? ...                                          */
;*---------------------------------------------------------------------*/
(define (connection-timeout? c now)
   (with-access::connection c (date)
      (let ((age (*fx 1000 (elong->fixnum (-elong now date)))))
	 (>=fx age (hop-remote-keep-alive-timeout)))))

;*---------------------------------------------------------------------*/
;*    connection-table-add! ...                                        */
;*---------------------------------------------------------------------*/
(define (connection-table-add! conn)
   (++ *keep-alive-connection-number*)
   (with-access::connection conn (key intable)
      (set! intable #t)
      (hashtable-update! *connection-table*
			 key
			 (lambda (l) (cons conn l))
			 (list conn))))

;*---------------------------------------------------------------------*/
;*    connection-table-remove! ...                                     */
;*---------------------------------------------------------------------*/
(define (connection-table-remove! conn)
   (-- *keep-alive-connection-number*)
   (with-access::connection conn (key intable)
      (set! intable #f)
      (hashtable-update! *connection-table*
			 key
			 (lambda (l) (remq! conn l))
			 '())))

;*---------------------------------------------------------------------*/
;*    filter-connection-table! ...                                     */
;*    -------------------------------------------------------------    */
;*    This function assumes *remote-lock* acquired.                    */
;*---------------------------------------------------------------------*/
(define (filter-connection-table! pred)
   
   (define (filter-connection! key conn)
      (if (pred conn)
	  (begin
	     (++ *keep-alive-connection-number*)
	     (hashtable-update! *connection-table*
				key
				(lambda (l) (cons conn l))
				(list conn)))
	  (begin
;* 	     (tprint "connection close/timeout " (connection-id conn)) */
	     (close-connection! conn))))
   
   [assert () (not (symbol? (mutex-state *remote-lock*)))]
   
   (with-trace 5 'filter-connection-table!
      ;; create a new hashtable
      (let ((otable *connection-table*))
	 (set! *connection-table* (make-hashtable))
	 ;; reset the number of connections
	 (set! *keep-alive-connection-number* 0)
	 ;; fill the new hashtable
	 (hashtable-for-each
	  otable
	  (lambda (key row)
	     (for-each (lambda (conn)
			  (filter-connection! key conn))
		       row))))))

;*---------------------------------------------------------------------*/
;*    remote-get-socket ...                                            */
;*    -------------------------------------------------------------    */
;*    This function is in charge of keeping alive remote connections.  */
;*    When a new connection to a remote host is to be opened,          */
;*    it first checks if it happens to still have an old connection    */
;*    with that host available for re-use.                             */
;*---------------------------------------------------------------------*/
(define (remote-get-socket host port timeout request ssl)
   
   (define (make-new-connection key id)
      (with-trace 4 'make-new-connection
	 (let ((s (make-client-socket/timeout host port timeout request ssl)))
;* 	    (tprint "make-new-connection id=" id)                      */
	    (instantiate::connection
	       (id id)
	       (socket s)
	       (host host)
	       (port port)
	       (key key)
	       (request-id (http-request-id request))
	       (date (current-seconds))
	       (locked #t)
	       (intable #f)))))

   (define (get-connection)
      (let ((key (string-append host ":" (integer->string port))))
	 (mutex-lock! *remote-lock*)
	 (let ((old (connection-table-get key)))
	    (if old
		(begin
		   (mutex-unlock! *remote-lock*)
		   old)
		(let ((id (+fx 1 *connection-id*)))
		   (set! *connection-id* id)
		   (++ *open-connection-number*)
		   (mutex-unlock! *remote-lock*)
		   (make-new-connection key id))))))

   (with-trace 4 'remote-get-connection
      (trace-item "host=" host)
      (if (not (hop-enable-remote-keep-alive))
	  (let ((id (+fx 1 *connection-id*)))
	     ;; id is not used unless remote connections are kept alive then
	     ;; we don't really a lock here to ensure a correct value
	     (set! *connection-id* id)
	     (make-new-connection host id))
	  (get-connection))))

;*---------------------------------------------------------------------*/
;*    too-many-keep-alive-connection? ...                              */
;*---------------------------------------------------------------------*/
(define (too-many-keep-alive-connection?)
   (>=fx *keep-alive-connection-number* (hop-max-remote-keep-alive-connection)))

;*---------------------------------------------------------------------*/
;*    connection-keep-alive! ...                                       */
;*---------------------------------------------------------------------*/
(define (connection-keep-alive! conn)
   (mutex-lock! *remote-lock*)
   (when (too-many-keep-alive-connection?)
      ;; we first try to cleanup the timeout connections
      (let ((now (current-seconds)))
	 (filter-connection-table!
	  (lambda (c)
	     (or (connection-locked c) (not (connection-timeout? c now)))))))
   (if (too-many-keep-alive-connection?)
       ;; we have failed, we still have too many keep-alive connections open
       (begin
	  (filter-connection-table! (lambda (c) (connection-locked c)))
	  (connection-close-sans-lock! conn))
       ;; store the connection only if room is available on the table
       (with-access::connection conn (locked keep-alive)
;* 	  (tprint "keep-alive connection : " (connection-id conn))     */
	  (set! locked #f)
	  (set! keep-alive #t)
	  (unless (connection-intable conn)
	     ;; this is the first time we see this connection, we add it to
	     ;; the connection table
	     (connection-table-add! conn))))
   (mutex-unlock! *remote-lock*))

;*---------------------------------------------------------------------*/
;*    connection-close-sans-lock! ...                                  */
;*---------------------------------------------------------------------*/
(define (connection-close-sans-lock! conn::connection)
   (with-access::connection conn (socket %%debug-closed)
      (when %%debug-closed
	 (error 'connection-close-sans-lock! "Connection already closed" conn))
      (close-connection! conn)
      (when (connection-intable conn)
	 (connection-table-remove! conn))))
   
;*---------------------------------------------------------------------*/
;*    connection-close! ...                                            */
;*---------------------------------------------------------------------*/
(define (connection-close! connection::connection)
   (mutex-lock! *remote-lock*)
   (connection-close-sans-lock! connection)
   (mutex-unlock! *remote-lock*))

;*---------------------------------------------------------------------*/
;*    connection-down? ...                                             */
;*---------------------------------------------------------------------*/
(define (connection-down? conn::connection)
   (let ((ip (connection-input conn)))
      (or (not (input-port? ip))
	  (when (char-ready? ip)
	     (with-handler
		(lambda (e)
		   #t)
		(let ((c (read-char ip)))
		   (if (eof-object? c)
		       #t
		       (let ((m (http-parse-error-message c ip)))
			  (raise
			   (instantiate::&io-parse-error
			      (proc "http-response")
			      (obj ip)
			      (msg (format "Illegal character: ~a" m))))))))))))

;*---------------------------------------------------------------------*/
;*    connection-output ...                                            */
;*---------------------------------------------------------------------*/
(define (connection-output connection::connection)
   (socket-output (connection-socket connection)))

;*---------------------------------------------------------------------*/
;*    connection-input ...                                             */
;*---------------------------------------------------------------------*/
(define (connection-input connection::connection)
   (socket-input (connection-socket connection)))