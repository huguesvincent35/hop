;*=====================================================================*/
;*    serrano/prgm/project/hop/3.0.x/nodejs/require.scm                */
;*    -------------------------------------------------------------    */
;*    Author      :  Manuel Serrano                                    */
;*    Creation    :  Mon Sep 16 15:47:40 2013                          */
;*    Last change :  Thu May 15 05:36:34 2014 (serrano)                */
;*    Copyright   :  2013-14 Manuel Serrano                            */
;*    -------------------------------------------------------------    */
;*    Native Bigloo Nodejs module implementation                       */
;*=====================================================================*/

;*---------------------------------------------------------------------*/
;*    The module                                                       */
;*---------------------------------------------------------------------*/
(module __nodejs_require

   (library hop hopscript js2scheme)

   (import __nodejs
	   __nodejs_process)

   (export (%nodejs-module::JsObject ::bstring ::bstring ::JsGlobalObject)
	   (nodejs-require ::bstring ::JsGlobalObject)
	   (nodejs-load ::bstring ::WorkerHopThread)
	   (nodejs-new-global-object::JsGlobalObject)
	   (nodejs-global-object-init! ::JsGlobalObject)))

;*---------------------------------------------------------------------*/
;*    %nodejs-module ...                                               */
;*---------------------------------------------------------------------*/
(define (%nodejs-module::JsObject id filename %this::JsGlobalObject)
   
   (define (nodejs-filename->paths::vector file::bstring)
      (if (char=? (string-ref file 0) #\/)
	  (let loop ((dir (dirname file))
		     (acc '()))
	     (if (string=? dir "/")
		 (list->vector
		    (reverse! (cons "/node_modules" acc)))
		 (loop (dirname dir)
		    (cons (make-file-name dir "node_modules") acc))))
	  '#()))
   
   (define (module-init! m exports)
      ;; id field
      (js-put! m 'id id #f %this)
      ;; exports
      (js-put! m 'exports exports #f %this)
      ;; filename
      (js-put! m 'filename filename #f %this)
      ;; loaded
      (js-put! m 'loaded #t #f %this)
      ;; children
      (js-put! m 'children '#() #f %this)
      ;; paths
      (js-put! m 'paths (nodejs-filename->paths filename) #f %this))
   
   (with-trace 1 "%nodejs-module"
      (trace-item "id=" id)
      (trace-item "filename=" filename)
      (with-access::JsGlobalObject %this (js-object)
	 (let ((m (js-new %this js-object))
	       (exports (js-new %this js-object)))
	    ;; module properties
	    (module-init! m exports)
	    ;; reqgister the module in the current worker thread
	    (nodejs-cache-module-put! filename (js-current-worker) m)
	    ;; global object exports
	    (js-put! %this 'exports exports #f %this)
	    ;; bind the module at once
	    (js-put! %this 'module m #f %this)
	    ;; return the newly allocated module
	    m))))

;*---------------------------------------------------------------------*/
;*    nodejs-require ...                                               */
;*    -------------------------------------------------------------    */
;*    Require a nodejs module, load it if necessary or simply          */
;*    reuse the previously loaded module structure.                    */
;*---------------------------------------------------------------------*/
(define (nodejs-require name %this)
   (with-trace 1 "nodejs-require"
      (trace-item "name=" name)
      (let ((worker (js-current-worker)))
	 (if (core-module? name)
	     (js-get (nodejs-load-core-module name worker %this) 'exports %this)
	     (let ((abspath (nodejs-resolve name %this)))
		(if (and (string? abspath) (file-exists? abspath))
		    (js-get (nodejs-load abspath worker) 'exports %this)
		    (with-access::JsGlobalObject %this (js-uri-error)
		       (js-raise
			  (js-new %this js-uri-error
			     (format "Cannot find module ~s" name))))))))))

;*---------------------------------------------------------------------*/
;*    nodejs-new-global-object ...                                     */
;*---------------------------------------------------------------------*/
(define (nodejs-new-global-object)
   
   (define this (js-new-global-object))
   
   (define require
      (js-make-function this
	 (lambda (_ name)
	    (nodejs-require (js-tostring name this) this))
	 1 "require"))
   
   ;; process
   (js-put! this 'process (%nodejs-process this) #f this)
   ;; require
   (js-put! this 'require require #f this)
   ;; the global object
   this)

;*---------------------------------------------------------------------*/
;*    nodejs-global-object-init! ...                                   */
;*---------------------------------------------------------------------*/
(define (nodejs-global-object-init! this)
   ;; console
   (js-put! this 'console (nodejs-require "console" this) #f this)
   ;; timers
   (nodejs-import! this (nodejs-require "timers" this))
   ;; return the object
   this)
   
;*---------------------------------------------------------------------*/
;*    nodejs-load ...                                                  */
;*---------------------------------------------------------------------*/
(define (nodejs-load filename worker::WorkerHopThread)
   
   (define (load-module %this)
      (loading-file-set! filename)
      (let* ((mod (gensym))
	     (expr (call-with-input-file filename
		      (lambda (in)
			 (j2s-compile in
			    :module-main #f
			    :module-name (symbol->string mod)))))
	     (this (nodejs-global-object-init! (nodejs-new-global-object)))
	     (evmod (eval-module)))
	 ;; eval the compile module in the current environment
	 (unwind-protect
	    (begin
	       (for-each eval! expr)
	       ((eval! 'hopscript) this)
	       ;; return the newly created module
	       (js-get this 'module this))
	    (eval-module-set! evmod))))

   (with-trace 1 "nodejs-load"
      (trace-item "filename=" filename)
      (with-access::WorkerHopThread worker (module-mutex module-table %this)
	 (synchronize module-mutex
	    (or (hashtable-get module-table filename)
		(load-module %this))))))

;*---------------------------------------------------------------------*/
;*    nodejs-env-path ...                                              */
;*---------------------------------------------------------------------*/
(define (nodejs-env-path)
   (let ((env (getenv "NODE_PATH")))
      (if (string? env)
	  (unix-path->list env)
	  '())))

;*---------------------------------------------------------------------*/
;*    nodejs-resolve ...                                               */
;*    -------------------------------------------------------------    */
;*    Resolve the path name according to the current module path.      */
;*---------------------------------------------------------------------*/
(define (nodejs-resolve name::bstring %this::JsGlobalObject)
   
   (define (nodejs-resolve-package path)
      (let ((pkg (make-file-name path "package.json")))
	 (when (file-exists? pkg)
	    (call-with-input-file pkg
	       (lambda (in)
		  (let* ((o (js-json-parser in (js-undefined) %this))
			 (m (js-tostring (js-get o 'main %this) %this)))
		     (when (string? m)
			(make-file-name path m))))))))
   
   (define (suffix name)
      (if (string-suffix? ".js" name )
	  name
	  (string-append name ".js")))
   
   (define (package-or-file name)
      (if (directory? name)
	  (nodejs-resolve-package name)
	  (suffix name)))

   (cond
      ((string-null? name)
       #f)
      ((char=? (string-ref name 0) (file-separator))
       (package-or-file name))
      ((or (string-prefix? "./" name) (string-prefix? "../" name))
       (package-or-file (file-name-canonicalize! (make-file-path (pwd) name))))
      (else
       (let ((module (js-get %this 'module %this)))
	  (when (isa? module JsObject)
	     (any (lambda (dir)
		     (let ((path (make-file-name dir name)))
			(if (directory? path)
			    (nodejs-resolve-package path)
			    (let ((src (suffix path)))
			       (when (file-exists? src)
				  src)))))
		(append (vector->list (js-get module 'paths %this))
		   (nodejs-env-path))))))))

;*---------------------------------------------------------------------*/
;*    nodejs-cache-module ...                                          */
;*---------------------------------------------------------------------*/
(define (nodejs-cache-module name worker)
   (with-access::WorkerHopThread worker (module-table module-mutex)
      (synchronize module-mutex
	 (hashtable-get module-table name))))
   
;*---------------------------------------------------------------------*/
;*    nodejs-cache-module-put! ...                                     */
;*---------------------------------------------------------------------*/
(define (nodejs-cache-module-put! name worker module)
   (with-access::WorkerHopThread worker (module-table module-mutex)
      (synchronize module-mutex
	 (hashtable-put! module-table name module)
	 module)))

;*---------------------------------------------------------------------*/
;*    nodejs-import ...                                                */
;*    -------------------------------------------------------------    */
;*    Bind the exported binding into a global object.                  */
;*---------------------------------------------------------------------*/
(define (nodejs-import! %this e)
   ;; bind all the exported functions in the global object 
   (js-for-in e
      (lambda (p)
	 (let ((k (string->symbol p)))
	    (js-put! %this k (js-get e k %this) #f %this)))
      %this))
   
;*---------------------------------------------------------------------*/
;*    nodejs-load-core-module ...                                      */
;*---------------------------------------------------------------------*/
(define (nodejs-load-core-module name worker %this)
   
   (define (nodejs-init-core-module name %this)
      (with-trace 2 "nodejs-init-core-module"
	 (trace-item "name=" name)
	 (let ((this (nodejs-new-global-object)))
	    (let ((c (assoc name (core-module-table))))
	       (let ((m ((cdr c) this)))
		  ;; complete the global object initialization
		  (nodejs-global-object-init! this)
		  ;; return the module
		  m)))))

   (with-trace 1 "nodejs-load-core-module"
      (trace-item "name=" name)
      (trace-item "cache=" (nodejs-cache-module name worker))
      (or (nodejs-cache-module name worker)
	  (nodejs-init-core-module name %this))))

;*---------------------------------------------------------------------*/
;*    core-module? ...                                                 */
;*---------------------------------------------------------------------*/
(define (core-module? name)
   (assoc name (core-module-table)))

;*---------------------------------------------------------------------*/
;*    Bind the nodejs require function                                 */
;*---------------------------------------------------------------------*/
(js-worker-load-set! nodejs-require)
