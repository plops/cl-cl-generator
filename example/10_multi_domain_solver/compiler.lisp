(in-package :multi-domain-solver)

;;; ============================================================================
;;; 1. Symbolic Differentiator & Simplifier
;;; ============================================================================

(defun diff (expr var)
  "Recursively differentiate EXPR with respect to VAR."
  (cond
    ((equal expr var) 1)
    ((atom expr) 0)
    (t (case (car expr)
         (+ `(+ ,(diff (second expr) var) ,(diff (third expr) var)))
         (- `(- ,(diff (second expr) var) ,(diff (third expr) var)))
         (* (let ((u (second expr))
                  (v (third expr)))
              `(+ (* ,u ,(diff v var)) (* ,v ,(diff u var)))))
         (/ (let ((u (second expr))
                  (v (third expr)))
              `(/ (- (* ,(diff u var) ,v) (* ,u ,(diff v var))) (* ,v ,v))))
         (exp `(* (exp ,(second expr)) ,(diff (second expr) var)))
         (t 0)))))

(defun simplify (expr)
  "Simplify symbolic algebraic Lisp expressions."
  (if (atom expr)
      expr
      (let ((simplified-args (mapcar #'simplify (cdr expr))))
        (case (car expr)
          (+ (destructuring-bind (a &optional (b 0)) simplified-args
               (cond
                 ((equal a 0) b)
                 ((equal b 0) a)
                 ((and (numberp a) (numberp b)) (+ a b))
                 (t `(+ ,a ,b)))))
          (- (destructuring-bind (a &optional b) simplified-args
               (if b
                   (cond
                     ((equal b 0) a)
                     ((equal a 0) `(- ,b))
                     ((and (numberp a) (numberp b)) (- a b))
                     (t `(- ,a ,b)))
                   (cond
                     ((numberp a) (- a))
                     (t `(- ,a))))))
          (* (destructuring-bind (a b) simplified-args
               (cond
                 ((or (equal a 0) (equal b 0)) 0)
                 ((equal a 1) b)
                 ((equal b 1) a)
                 ((and (numberp a) (numberp b)) (* a b))
                 (t `(* ,a ,b)))))
          (/ (destructuring-bind (a b) simplified-args
               (cond
                 ((equal a 0) 0)
                 ((equal b 1) a)
                 ((and (numberp a) (numberp b)) (/ a b))
                 (t `(/ ,a ,b)))))
          (t (cons (car expr) simplified-args))))))

;;; ============================================================================
;;; 2. Symbolic Linear Solver (Gaussian Elimination with Partial Pivoting)
;;; ============================================================================

(defun solve-symbolic-system (mat-a vec-b vars)
  "Solves A * x = b symbolically where mat-a is a 2D array and vec-b is a 1D array.
   Returns a list of let-bindings (var expression) in order."
  (let* ((d (length vars))
         (a (make-array (list d d) :initial-contents mat-a))
         (b (make-array d :initial-contents vec-b)))
    ;; Forward elimination with partial pivoting
    (dotimes (i d)
      ;; Find pivot row (prefer rows with shorter symbolic expressions or non-zero numbers)
      (let ((pivot-row i))
        (loop for r from (1+ i) to (1- d)
              do (when (not (equal (aref a r i) 0))
                   (setf pivot-row r)
                   (return)))
        ;; Swap rows in A and b if needed
        (when (/= pivot-row i)
          (dotimes (j d)
            (rotatef (aref a i j) (aref a pivot-row j)))
          (rotatef (aref b i) (aref b pivot-row))))
      
      ;; Normalize row i
      (let ((pivot (aref a i i)))
        (when (equal pivot 0)
          (error "Zero pivot encountered at row ~a during symbolic solve!" i))
        (loop for j from i to (1- d)
              do (setf (aref a i j) (simplify `(/ ,(aref a i j) ,pivot))))
        (setf (aref b i) (simplify `(/ ,(aref b i) ,pivot))))
      
      ;; Eliminate column i from subsequent rows
      (loop for k from (1+ i) to (1- d)
            do (let ((factor (aref a k i)))
                 (unless (equal factor 0)
                   (loop for j from i to (1- d)
                         do (setf (aref a k j) (simplify `(- ,(aref a k j) (* ,factor ,(aref a i j))))))
                   (setf (aref b k) (simplify `(- ,(aref b k) (* ,factor ,(aref b i)))))))))
    
    ;; Back substitution
    (loop for i from (1- d) downto 0
          do (loop for k from (1- i) downto 0
                   do (let ((factor (aref a k i)))
                        (unless (equal factor 0)
                          (setf (aref b k) (simplify `(- ,(aref b k) (* ,factor ,(aref b i)))))))))
    
    ;; Return list of bindings
    (loop for i from 0 to (1- d)
          collect (list (nth i vars) (aref b i)))))

;;; ============================================================================
;;; 3. Netlist MNA Parser & Matrix Assembler
;;; ============================================================================

(defun get-nodes (netlist)
  "Get all unique nodes in the netlist, excluding ground 0."
  (let ((nodes nil))
    (dolist (elem netlist)
      (let ((el-nodes (getf (cddr elem) :nodes)))
        (dolist (n el-nodes)
          (unless (or (eql n 0) (member n nodes))
            (push n nodes)))))
    (sort nodes #'<)))

(defun compile-netlist-to-file (filename netlist &key (dt 1d-3) (directory *default-pathname-defaults*))
  "Compile a multi-domain netlist into a fast, zero-allocation Lisp solver file."
  (let* ((nodes (get-nodes netlist))
         (num-nodes (length nodes))
         ;; Map node names to 0-indexed positions in node vector
         (node-map (loop for n in nodes for idx from 0 collect (cons n idx)))
         
         ;; Identify branch current variables
         (across-sources nil)
         (inductances nil)
         (diodes nil))
    (flet ((get-node-idx (n) (cdr (assoc n node-map))))
      ;; Classify components
      (dolist (elem netlist)
        (let ((type (car elem))
              (name (second elem))
              (props (cddr elem)))
          (case type
            ((voltage-source velocity-source temperature-source pressure-source)
             (push (list name :nodes (getf props :nodes) :value (getf props :value)) across-sources))
            (inductor
             (push (list name :nodes (getf props :nodes) :value (getf props :value)) inductances))
            (diode
             (push (list name :nodes (getf props :nodes)
                               :is (getf props :is 1d-14)
                               :vt (getf props :vt 0.026d0)) diodes)))))
      
      (setf across-sources (nreverse across-sources)
            inductances (nreverse inductances)
            diodes (nreverse diodes))
      
      ;; Build list of variables in system:
      ;; x = [v1, ..., vN, j_src1, ..., i_ind1, ...]
      (let* ((node-vars (mapcar (lambda (n) (intern (format nil "V-~a" n))) nodes))
             (src-vars (mapcar (lambda (src) (intern (format nil "J-~a" (car src)))) across-sources))
             (ind-vars (mapcar (lambda (ind) (intern (format nil "I-~a" (car ind)))) inductances))
             (vars (append node-vars src-vars ind-vars))
             (d (length vars))
             ;; Setup symbolic matrix A and vector B
             (mat-a (loop for i from 0 to (1- d) collect (make-list d :initial-element 0)))
             (vec-b (make-list d :initial-element 0))
             
             ;; Create state variables to track historical values
             (prev-vars nil)
             (initial-states nil)
             (state-updates nil))
        
        (labels ((add-a (r c val)
                   (when (and r c)
                     (let ((row (nth r mat-a)))
                       (setf (nth c row) (simplify `(+ ,(nth c row) ,val))))))
                 (add-b (r val)
                   (when r
                     (setf (nth r vec-b) (simplify `(+ ,(nth r vec-b) ,val))))))
          
          ;; 1. Process linear Conductances (Resistors, Dampers, etc.)
          (dolist (elem netlist)
            (let ((type (car elem))
                  (props (cddr elem)))
              (when (member type '(resistor damper thermal-resistor fluid-resistance))
                (let* ((nodes (getf props :nodes))
                       (n1 (get-node-idx (first nodes)))
                       (n2 (get-node-idx (second nodes)))
                       (val (getf props :value))
                       ;; Conductance G = 1/R
                       (g (if (member type '(damper fluid-resistance)) val `(/ 1.0d0 ,val))))
                  (add-a n1 n1 g)
                  (add-a n2 n2 g)
                  (add-a n1 n2 `(- ,g))
                  (add-a n2 n1 `(- ,g))))))
          
          ;; 2. Process Capacities (Capacitors, Masses, Thermal Capacity, etc.)
          (dolist (elem netlist)
            (let ((type (car elem))
                  (name (second elem))
                  (props (cddr elem)))
              (when (member type '(capacitor mass thermal-capacity fluid-capacity))
                (let* ((nodes (getf props :nodes))
                       (n1 (get-node-idx (first nodes)))
                       (n2 (get-node-idx (second nodes)))
                       (val (getf props :value))
                       (c-over-h `(/ ,val ,dt))
                       ;; We need to track the previous voltage across capacity
                       (prev-name (intern (format nil "PREV-VC-~a" name))))
                  (push prev-name prev-vars)
                  (push 0.0d0 initial-states)
                  
                  ;; Add capacity stamp to linear matrix
                  (add-a n1 n1 c-over-h)
                  (add-a n2 n2 c-over-h)
                  (add-a n1 n2 `(- ,c-over-h))
                  (add-a n2 n1 `(- ,c-over-h))
                  
                  ;; Add historical current source to RHS
                  (add-b n1 `(* ,c-over-h ,prev-name))
                  (add-b n2 `(- (* ,c-over-h ,prev-name)))
                  
                  ;; Define state update at end of step
                  (push `(setf ,prev-name (- ,(if n1 (nth n1 node-vars) 0.0d0)
                                             ,(if n2 (nth n2 node-vars) 0.0d0)))
                        state-updates)))))
          
          ;; 3. Process Inductances (Inductors, Springs, Fluid Inertia, etc.)
          (loop for ind in inductances
                for idx from 0
                do (let* ((name (car ind))
                          (nodes (getf (cdr ind) :nodes))
                          (n1 (get-node-idx (first nodes)))
                          (n2 (get-node-idx (second nodes)))
                          (val (getf (cdr ind) :value))
                          ;; For springs, L = 1/k
                          (l (if (eq (car ind) 'spring) `(/ 1.0d0 ,val) val))
                          (l-over-h `(/ ,l ,dt))
                          (var-idx (+ num-nodes (length across-sources) idx))
                          (prev-name (intern (format nil "PREV-IL-~a" name))))
                     (push prev-name prev-vars)
                     (push 0.0d0 initial-states)
                     
                     ;; Node equations get inductor branch current
                     (add-a n1 var-idx 1.0d0)
                     (add-a n2 var-idx -1.0d0)
                     ;; Inductor branch equation: v1 - v2 - (L/h)*iL = -(L/h)*iL_prev
                     (add-a var-idx n1 1.0d0)
                     (add-a var-idx n2 -1.0d0)
                     (add-a var-idx var-idx `(- ,l-over-h))
                     (add-b var-idx `(- (* ,l-over-h ,prev-name)))
                     
                     ;; Define state update at end of step
                     (push `(setf ,prev-name ,(nth var-idx vars)) state-updates)))
          
          ;; 4. Process Across Sources
          (loop for src in across-sources
                for idx from 0
                do (let* ((name (car src))
                          (nodes (getf (cdr src) :nodes))
                          (n1 (get-node-idx (first nodes)))
                          (n2 (get-node-idx (second nodes)))
                          (val (getf (cdr src) :value))
                          (var-idx (+ num-nodes idx)))
                     ;; Node equations get source current
                     (add-a n1 var-idx 1.0d0)
                     (add-a n2 var-idx -1.0d0)
                     ;; Source branch equation: v1 - v2 = V_src
                     (add-a var-idx n1 1.0d0)
                     (add-a var-idx n2 -1.0d0)
                     (add-b var-idx val)))
          
          ;; 5. Process Through Sources (inject flow directly to nodes)
          (dolist (elem netlist)
            (let ((type (car elem))
                  (props (cddr elem)))
              (when (member type '(current-source force-source heat-source flow-source))
                (let* ((nodes (getf props :nodes))
                       (n1 (get-node-idx (first nodes)))
                       (n2 (get-node-idx (second nodes)))
                       (val (getf props :value)))
                  (add-b n1 val)
                  (add-b n2 `(- ,val)))))))
        
        (setf prev-vars (nreverse prev-vars)
              initial-states (nreverse initial-states)
              state-updates (nreverse state-updates))
        
        ;; 6. Assemble Newton-Raphson Solver if non-linear elements (Diodes) exist
        (let* ((has-diodes-p (not (null diodes)))
               (solved-bindings
                 (solve-symbolic-system mat-a vec-b vars)))
          
          ;; Write output file using cl-cl-generator
          (write-source filename
            `(toplevel
               (in-package :multi-domain-solver)
               
               (defstruct sim-state
                 (time 0.0d0 :type double-float)
                 ,@(loop for p in prev-vars
                         for init in initial-states
                         collect `(,p ,init :type double-float))
                 ,@(loop for v in vars
                         collect `(,v 0.0d0 :type double-float)))
               
               (defun step-simulation (state dt f-ext)
                 (declare (type sim-state state)
                          (type double-float dt f-ext)
                          (optimize (speed 3) (safety 0)))
                 (let* ((time (sim-state-time state))
                        ;; Extract previous state variables
                        ,@(loop for p in prev-vars
                                collect `(,p (,(intern (format nil "SIM-STATE-~a" p)) state)))
                        ;; Extract current variables as starting guess
                        ,@(loop for v in vars
                                collect `(,v (,(intern (format nil "SIM-STATE-~a" v)) state))))
                   (declare (type double-float time ,@prev-vars ,@vars))
                   
                   ;; Newton-Raphson Solver Loop
                   ,(if has-diodes-p
                        `(let ((converged nil))
                           (dotimes (iter 20)
                             (unless converged
                               ;; Compute non-linear currents and conductances (diode jacobian)
                               (let* (,@(loop for d in diodes
                                              collect (let* ((nodes (getf (cdr d) :nodes))
                                                             (n1 (get-node-idx (first nodes)))
                                                             (n2 (get-node-idx (second nodes)))
                                                             (vn1 (if n1 (nth n1 node-vars) 0.0d0))
                                                             (vn2 (if n2 (nth n2 node-vars) 0.0d0))
                                                             (vd `(- ,vn1 ,vn2))
                                                             (is (getf (cdr d) :is))
                                                             (vt (getf (cdr d) :vt)))
                                                        ;; Local bindings for diode current & conductance
                                                        `((,(intern (format nil "ID-~a" (car d))) (* ,is (- (exp (/ ,vd ,vt)) 1.0d0)))
                                                          (,(intern (format nil "GD-~a" (car d))) (* (/ ,is ,vt) (exp (/ ,vd ,vt))))))))
                                      ;; Re-evaluate matrix A with diode conductance and solve
                                      ;; [Insert symbolic solver steps for Jacobian matrix J * dx = -F]
                                      )
                                     )))
                        ;; Linear system: Solve directly in one step!
                        `(let* (,@solved-bindings)
                           ;; Update simulation state values
                           ,@(loop for v in vars
                                   collect `(setf (,(intern (format nil "SIM-STATE-~a" v)) state) ,v))
                           ;; Apply state updates for next step
                           ,@(loop for update in state-updates
                                   collect `(let (,@(loop for v in vars collect `(,v ,v)))
                                              ,update))
                           (incf (sim-state-time state) dt)))
                   state))
               
               (defun run-simulation-steps (steps &key (time-step ,dt) (force 0.0d0))
                 (declare (type integer steps)
                          (type double-float time-step force))
                 (let ((state (make-sim-state))
                       (results nil))
                   (dotimes (i steps)
                     (step-simulation state time-step force)
                     ;; Record time and variables
                     (push (list (sim-state-time state)
                                 ,@(loop for v in vars
                                         collect `(,(intern (format nil "SIM-STATE-~a" v)) state)))
                           results))
                   (nreverse results)))
               )
            directory))))))
