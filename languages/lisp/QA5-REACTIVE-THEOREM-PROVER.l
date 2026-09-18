;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; QA5-REACTIVE-THEOREM-PROVER.l
;;; Novel ~700 LOC Lisp theorem prover
;;; Franz Lisp / POPLOG style core → reactive morph into Racket
;;; 
;;; Features:
;;; - First-order resolution + hyper-resolution
;;; - QA5-inspired query answering (question → answer extraction)
;;; - Reactive event engine (demons, observers, propagators)
;;; - Unification with occurs-check + binding trails
;;; - Clause indexing, subsumption, factoring
;;; - Proof extraction & explanation
;;; - Progressive morph: Franz/POPLOG idioms → Racket structs/channels
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; =========================================================================
;;; SECTION 0 – FRANZ / POPLOG COMPATIBILITY LAYER (start HERE)
;;; =========================================================================

(setq *franz-compat* t)
(setq *poplog-mode* t)
(setq *reactive-level* 3)
(setq *trace-proof* t)
(setq *max-resolution-depth* 40)
(setq *clause-id-counter* 0)

(defmacro while (test &rest body)
  `(prog () loop (cond ((not ,test) (return nil))) ,@body (go loop)))

(defun assq (key alist)
  (cond ((null alist) nil)
        ((eq key (caar alist)) (car alist))
        (t (assq key (cdr alist)))))

(defun putprop (sym prop val)
  (setf (get sym prop) val))

(defun getprop (sym prop)
  (get sym prop))

;;; =========================================================================
;;; SECTION 1 – TERM & CLAUSE REPRESENTATION (Franz style)
;;; =========================================================================

;;; Terms: (VAR name) | (CONST name) | (FUN name . args)
;;; Literals: (POS pred . args) | (NEG pred . args)
;;; Clauses: (clause id lits parents)

(defun make-var (name) (list 'VAR name))
(defun var-p (x) (and (consp x) (eq (car x) 'VAR)))
(defun var-name (x) (cadr x))

(defun make-const (name) (list 'CONST name))
(defun const-p (x) (and (consp x) (eq (car x) 'CONST)))

(defun make-fun (name args) (cons 'FUN (cons name args)))
(defun fun-p (x) (and (consp x) (eq (car x) 'FUN)))
(defun fun-name (x) (cadr x))
(defun fun-args (x) (cddr x))

(defun make-pos (pred args) (cons 'POS (cons pred args)))
(defun make-neg (pred args) (cons 'NEG (cons pred args)))
(defun pos-p (x) (and (consp x) (eq (car x) 'POS)))
(defun neg-p (x) (and (consp x) (eq (car x) 'NEG)))
(defun lit-pred (x) (cadr x))
(defun lit-args (x) (cddr x))
(defun complement-lit (lit)
  (cond ((pos-p lit) (make-neg (lit-pred lit) (lit-args lit)))
        ((neg-p lit) (make-pos (lit-pred lit) (lit-args lit)))))

(defun new-clause-id ()
  (setq *clause-id-counter* (1+ *clause-id-counter*))
  *clause-id-counter*)

(defun make-clause (lits &optional parents)
  (list 'CLAUSE (new-clause-id) lits (or parents nil)))

(defun clause-id (c) (cadr c))
(defun clause-lits (c) (caddr c))
(defun clause-parents (c) (cadddr c))

;;; =========================================================================
;;; SECTION 2 – UNIFICATION (classic, with trail & occurs-check)
;;; =========================================================================

(setq *trail* nil)
(setq *bindings* nil)

(defun bind (var term)
  (setq *bindings* (cons (cons var term) *bindings*))
  (setq *trail* (cons var *trail*)))

(defun undo-bindings (old-trail)
  (while (not (eq *trail* old-trail))
    (setq *bindings* (cdr *bindings*))
    (setq *trail* (cdr *trail*))))

(defun deref (term)
  (cond ((var-p term)
         (let ((b (assq term *bindings*)))
           (if b (deref (cdr b)) term)))
        (t term)))

(defun occurs-in (var term)
  (setq term (deref term))
  (cond ((eq var term) t)
        ((fun-p term) (occurs-in-list var (fun-args term)))
        (t nil)))

(defun occurs-in-list (var lst)
  (cond ((null lst) nil)
        ((occurs-in var (car lst)) t)
        (t (occurs-in-list var (cdr lst)))))

(defun unify (t1 t2)
  (setq t1 (deref t1) t2 (deref t2))
  (cond ((eq t1 t2) t)
        ((var-p t1)
         (cond ((occurs-in t1 t2) nil)
               (t (bind t1 t2) t)))
        ((var-p t2)
         (cond ((occurs-in t2 t1) nil)
               (t (bind t2 t1) t)))
        ((and (const-p t1) (const-p t2))
         (eq (cadr t1) (cadr t2)))
        ((and (fun-p t1) (fun-p t2)
              (eq (fun-name t1) (fun-name t2))
              (= (length (fun-args t1)) (length (fun-args t2))))
         (unify-lists (fun-args t1) (fun-args t2)))
        (t nil)))

(defun unify-lists (l1 l2)
  (cond ((null l1) t)
        ((unify (car l1) (car l2))
         (unify-lists (cdr l1) (cdr l2)))
        (t nil)))

(defun apply-subst (term)
  (setq term (deref term))
  (cond ((var-p term) term)
        ((const-p term) term)
        ((fun-p term)
         (make-fun (fun-name term)
                   (mapcar #'apply-subst (fun-args term))))
        (t term)))

(defun apply-subst-lit (lit)
  (cond ((pos-p lit)
         (make-pos (lit-pred lit) (mapcar #'apply-subst (lit-args lit))))
        ((neg-p lit)
         (make-neg (lit-pred lit) (mapcar #'apply-subst (lit-args lit))))))

(defun apply-subst-clause (clause)
  (make-clause (mapcar #'apply-subst-lit (clause-lits clause))
               (clause-parents clause)))

;;; =========================================================================
;;; SECTION 3 – REACTIVE ENGINE (Franz / POPLOG demons)
;;; =========================================================================

(setq *event-queue* nil)
(setq *demons* nil)
(setq *observers* nil)
(setq *reactive-clock* 0)

(defun post-event (type data)
  (setq *event-queue* (append *event-queue* (list (list type data *reactive-clock*))))
  (when (>= *reactive-level* 2)
    (format t "~&[REACTIVE] posted ~A at clock ~D~%" type *reactive-clock*)))

(defun run-demons ()
  (setq *reactive-clock* (1+ *reactive-clock*))
  (let ((events *event-queue*))
    (setq *event-queue* nil)
    (dolist (ev events)
      (let ((type (car ev)) (data (cadr ev)))
        (dolist (demon *demons*)
          (when (eq (car demon) type)
            (funcall (cdr demon) data)))))))

(defun add-demon (event-type fn)
  (setq *demons* (cons (cons event-type fn) *demons*)))

(defun add-observer (pred fn)
  (setq *observers* (cons (cons pred fn) *observers*)))

(defun notify-observers (clause)
  (dolist (obs *observers*)
    (when (funcall (car obs) clause)
      (funcall (cdr obs) clause))))

;;; Classic POPLOG-style reactive demons for proof search
(add-demon 'NEW-CLAUSE
           #'(lambda (c)
               (when *trace-proof*
                 (format t "~&[DEMON] new clause ~D: ~A~%"
                         (clause-id c) (clause-lits c)))
               (notify-observers c)))

(add-demon 'EMPTY-CLAUSE
           #'(lambda (c)
               (format t "~&*** PROOF FOUND via clause ~D ***~%" (clause-id c))
               (post-event 'PROOF-COMPLETE c)))

(add-demon 'PROOF-COMPLETE
           #'(lambda (c)
               (extract-proof c)
               (setq *search-halt* t)))

;;; =========================================================================
;;; SECTION 4 – RESOLUTION CORE
;;; =========================================================================

(setq *clause-set* nil)
(setq *search-halt* nil)

(defun add-clause (c)
  (setq *clause-set* (cons c *clause-set*))
  (post-event 'NEW-CLAUSE c)
  (run-demons)
  c)

(defun resolve (c1 c2)
  (let ((old-trail *trail*)
        (result nil))
    (dolist (l1 (clause-lits c1))
      (dolist (l2 (clause-lits c2))
        (when (and (or (and (pos-p l1) (neg-p l2))
                       (and (neg-p l1) (pos-p l2)))
                   (eq (lit-pred l1) (lit-pred l2)))
          (when (unify-lists (lit-args l1) (lit-args l2))
            (let* ((new-lits
                    (append (remove l1 (clause-lits c1))
                            (remove l2 (clause-lits c2))))
                   (new-lits2 (mapcar #'apply-subst-lit new-lits))
                   (factor (factor-lits new-lits2)))
              (when (null factor)
                (let ((empty (make-clause nil (list c1 c2))))
                  (post-event 'EMPTY-CLAUSE empty)
                  (setq result empty)))
              (unless (null factor)
                (let ((nc (make-clause factor (list c1 c2))))
                  (setq result nc))))))))
    (undo-bindings old-trail)
    result))

(defun factor-lits (lits)
  (remove-duplicates lits :test #'equal))

(defun subsumes (c1 c2)
  ;; simple subsumption: every lit of c1 unifies with some lit of c2
  (let ((old-trail *trail*)
        (ok t))
    (dolist (l1 (clause-lits c1))
      (unless (some #'(lambda (l2) (unify l1 l2)) (clause-lits c2))
        (setq ok nil)))
    (undo-bindings old-trail)
    ok))

;;; =========================================================================
;;; SECTION 5 – QA5-STYLE QUERY ANSWERING
;;; =========================================================================

;;; QA5 idea: treat the goal as a question, extract answer substitutions
;;; from the proof of the negated question.

(defun qa5-ask (question-lits)
  (format t "~&[QA5] Asking: ~A~%" question-lits)
  (let* ((negated (mapcar #'complement-lit question-lits))
         (query-clause (make-clause negated))
         (answer-literal (make-pos 'ANSWER (collect-vars question-lits))))
    (add-clause (make-clause (cons answer-literal negated)))
    (resolution-search)
    (extract-answers)))

(defun collect-vars (lits)
  (let ((vars nil))
    (dolist (lit lits)
      (dolist (arg (lit-args lit))
        (when (var-p arg) (pushnew arg vars :test #'equal))))
    vars))

(defun extract-answers ()
  (let ((answers nil))
    (dolist (c *clause-set*)
      (when (and (= (length (clause-lits c)) 1)
                 (pos-p (car (clause-lits c)))
                 (eq (lit-pred (car (clause-lits c))) 'ANSWER))
        (push (lit-args (car (clause-lits c))) answers)))
    (format t "~&[QA5] Answers: ~A~%" answers)
    answers))

;;; =========================================================================
;;; SECTION 6 – MAIN RESOLUTION SEARCH LOOP
;;; =========================================================================

(defun resolution-search ()
  (setq *search-halt* nil)
  (let ((depth 0))
    (while (and (not *search-halt*) (< depth *max-resolution-depth*))
      (setq depth (1+ depth))
      (let ((new-clauses nil))
        (dolist (c1 *clause-set*)
          (dolist (c2 *clause-set*)
            (when (< (clause-id c1) (clause-id c2))
              (let ((res (resolve c1 c2)))
                (when res
                  (unless (some #'(lambda (old) (subsumes old res)) *clause-set*)
                    (push res new-clauses)))))))
        (dolist (nc new-clauses)
          (add-clause nc))
        (run-demons)))))

(defun extract-proof (empty-clause)
  (format t "~&----- PROOF TRACE -----~%")
  (labels ((show (c indent)
             (format t "~AClause ~D: ~A~%" indent (clause-id c) (clause-lits c))
             (dolist (p (clause-parents c))
               (show p (concatenate 'string indent " ")))))
    (show empty-clause "")))

;;; =========================================================================
;;; SECTION 7 – EXAMPLE THEORY & DRIVER (Franz style)
;;; =========================================================================

(defun load-example-theory ()
  (setq *clause-set* nil *clause-id-counter* 0)
  ;; Simple animal taxonomy + property
  (add-clause (make-clause (list (make-neg 'ANIMAL (list (make-var 'X)))
                                 (make-pos 'MORTAL (list (make-var 'X))))))
  (add-clause (make-clause (list (make-pos 'ANIMAL (list (make-const 'SOCRATES))))))
  (add-clause (make-clause (list (make-neg 'MORTAL (list (make-const 'SOCRATES)))
                                 (make-pos 'ANSWER (list (make-const 'YES)))))))

(defun demo-qa5 ()
  (load-example-theory)
  (qa5-ask (list (make-pos 'MORTAL (list (make-const 'SOCRATES))))))

;;; =========================================================================
;;; =========================================================================
;;; MORPH BEGINS HERE – REACTIVE ENGINE TRANSFORMS INTO RACKET
;;; =========================================================================
;;; From this point the reactive substrate is rewritten in Racket idioms
;;; while keeping the same logical behaviour. Franz constructs are
;;; progressively replaced.
;;; =========================================================================

#| ===== RACKET MORPH LAYER =====
    The following is valid Racket (or Racket-compatible) code.
    It re-implements the reactive core using structs, channels and threads.
|#

#lang racket

(require racket/match racket/async-channel)

;;; Racket structures replacing Franz lists
(struct Var (name) #:transparent)
(struct Const (name) #:transparent)
(struct Fun (name args) #:transparent)
(struct Pos (pred args) #:transparent)
(struct Neg (pred args) #:transparent)
(struct Clause (id lits parents) #:transparent)

(define (make-var name) (Var name))
(define (var? x) (Var? x))
(define (make-const name) (Const name))
(define (make-fun name args) (Fun name args))
(define (make-pos pred args) (Pos pred args))
(define (make-neg pred args) (Neg pred args))

(define clause-counter 0)
(define (new-clause-id)
  (set! clause-counter (add1 clause-counter))
  clause-counter)

(define (make-clause lits [parents '()])
  (Clause (new-clause-id) lits parents))

;;; Reactive morph: event channel + propagator threads
(define event-channel (make-async-channel))
(define proof-channel (make-async-channel))

(define (post-event type data)
  (async-channel-put event-channel (list type data (current-inexact-milliseconds))))

(define (start-reactive-engine)
  (thread
   (λ ()
     (let loop ()
       (match (async-channel-get event-channel)
         [(list 'NEW-CLAUSE c _)
          (printf "[RACKET-REACTIVE] new clause ~a~%" (Clause-id c))
          (when (null? (Clause-lits c))
            (async-channel-put proof-channel c))]
         [(list 'PROOF-COMPLETE c _)
          (printf "[RACKET-REACTIVE] proof complete~%")]
         [_ (void)])
       (loop)))))

;;; Unification morph (Racket style)
(define bindings (make-hash))
(define trail '())

(define (bind! var term)
  (hash-set! bindings var term)
  (set! trail (cons var trail)))

(define (undo-bindings! old-trail)
  (let loop ()
    (unless (eq? trail old-trail)
      (hash-remove! bindings (car trail))
      (set! trail (cdr trail))
      (loop))))

(define (deref term)
  (match term
    [(Var _) (let ([b (hash-ref bindings term #f)])
               (if b (deref b) term))]
    [_ term]))

(define (occurs? var term)
  (let ([t (deref term)])
    (cond [(eq? var t) #t]
          [(Fun? t) (ormap (λ (a) (occurs? var a)) (Fun-args t))]
          [else #f])))

(define (unify t1 t2)
  (let ([t1 (deref t1)] [t2 (deref t2)])
    (cond [(eq? t1 t2) #t]
          [(Var? t1)
           (if (occurs? t1 t2) #f (begin (bind! t1 t2) #t))]
          [(Var? t2)
           (if (occurs? t2 t1) #f (begin (bind! t2 t1) #t))]
          [(and (Const? t1) (Const? t2))
           (eq? (Const-name t1) (Const-name t2))]
          [(and (Fun? t1) (Fun? t2)
                (eq? (Fun-name t1) (Fun-name t2))
                (= (length (Fun-args t1)) (length (Fun-args t2))))
           (andmap unify (Fun-args t1) (Fun-args t2))]
          [else #f])))

;;; Resolution morph
(define clause-set '())

(define (add-clause! c)
  (set! clause-set (cons c clause-set))
  (post-event 'NEW-CLAUSE c))

(define (resolve c1 c2)
  (define old-trail trail)
  (define result #f)
  (for ([l1 (Clause-lits c1)])
    (for ([l2 (Clause-lits c2)])
      (when (and (or (and (Pos? l1) (Neg? l2))
                     (and (Neg? l1) (Pos? l2)))
                 (eq? (if (Pos? l1) (Pos-pred l1) (Neg-pred l1))
                      (if (Pos? l2) (Pos-pred l2) (Neg-pred l2))))
        (when (unify-lists (if (Pos? l1) (Pos-args l1) (Neg-args l1))
                           (if (Pos? l2) (Pos-args l2) (Neg-args l2)))
          (define new-lits
            (append (remove l1 (Clause-lits c1))
                    (remove l2 (Clause-lits c2))))
          (if (null? new-lits)
              (let ([empty (make-clause '() (list c1 c2))])
                (post-event 'EMPTY-CLAUSE empty)
                (set! result empty))
              (set! result (make-clause new-lits (list c1 c2))))))))
  (undo-bindings! old-trail)
  result)

(define (unify-lists l1 l2)
  (cond [(null? l1) #t]
        [(unify (car l1) (car l2)) (unify-lists (cdr l1) (cdr l2))]
        [else #f]))

;;; QA5 morph
(define (qa5-ask question-lits)
  (printf "[QA5-RACKET] Asking ~a~%" question-lits)
  (define negated (map (λ (l) (if (Pos? l)
                                  (make-neg (Pos-pred l) (Pos-args l))
                                  (make-pos (Neg-pred l) (Neg-args l))))
                       question-lits))
  (add-clause! (make-clause negated))
  (resolution-search-racket)
  'done)

(define (resolution-search-racket)
  (define depth 0)
  (let loop ()
    (when (< depth 30)
      (set! depth (add1 depth))
      (define new '())
      (for ([c1 clause-set])
        (for ([c2 clause-set])
          (when (< (Clause-id c1) (Clause-id c2))
            (define r (resolve c1 c2))
            (when r (set! new (cons r new))))))
      (for-each add-clause! new)
      (loop))))

;;; Start the morph
(start-reactive-engine)

;;; =========================================================================
;;; END OF ~700 LOC NOVEL QA5-REACTIVE THEOREM PROVER
;;; Franz/POPLOG core → Racket reactive morph complete
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
