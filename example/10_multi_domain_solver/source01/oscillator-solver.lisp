(in-package :multi-domain-solver)

(defstruct sim-state
  (time 0.0d0 :type double-float)
  (prev-vc-m1 0.0d0 :type double-float)
  (prev-il-k1 0.0d0 :type double-float)
  (v-1 0.0d0 :type double-float)
  (i-k1 0.0d0 :type double-float))

(defun step-simulation (state dt f-ext)
  (declare (type sim-state state)
           (type double-float dt f-ext)
           (optimize (speed 3) (safety 0)))
  (let* ((time (sim-state-time state))
         (prev-vc-m1 (sim-state-prev-vc-m1 state))
         (prev-il-k1 (sim-state-prev-il-k1 state)) (v-1 (sim-state-v-1 state))
         (i-k1 (sim-state-i-k1 state)))
    (declare (type double-float time prev-vc-m1 prev-il-k1 v-1 i-k1))
    (let* ((v-1
            (- (/ (- (* 2.0d0 prev-il-k1)) 1.0d0)
               (* -2.0d0
                  (/
                   (- (+ (* 40.0d0 prev-vc-m1) f-ext)
                      (* 40.5d0 (/ (- (* 2.0d0 prev-il-k1)) 1.0d0)))
                   82.0d0))))
           (i-k1
            (/
             (- (+ (* 40.0d0 prev-vc-m1) f-ext)
                (* 40.5d0 (/ (- (* 2.0d0 prev-il-k1)) 1.0d0)))
             82.0d0)))
      (setf (sim-state-v-1 state) v-1)
      (setf (sim-state-i-k1 state) i-k1)
      (let ((v-1 v-1) (i-k1 i-k1))
        (setf prev-vc-m1 (- v-1 0.0d0)))
      (let ((v-1 v-1) (i-k1 i-k1))
        (setf prev-il-k1 i-k1))
      (incf (sim-state-time state) dt))
    state))

(defun run-simulation-steps (steps &key (time-step 0.05d0) (force 0.0d0))
  (declare (type integer steps)
           (type double-float time-step force))
  (let ((state (make-sim-state)) (results nil))
    (dotimes (i steps)
      (step-simulation state time-step force)
      (push
       (list (sim-state-time state) (sim-state-v-1 state)
             (sim-state-i-k1 state))
       results))
    (nreverse results)))