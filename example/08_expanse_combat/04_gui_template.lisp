;;;; 04_gui_template.lisp — X11 GUI and Elm-style game loop template for example 08

(in-package :cl-cl-generator/example-expanse-gen)

(defparameter *gui-template-code*
  `(toplevel
     ,@(make-header-comments)
     (defpackage :expanse-combat/game
       (:use :cl :pure-x11-gen :expanse-combat/physics :expanse-combat/mpc)
       (:export #:run-game))
     (in-package :expanse-combat/game)

     ;; --- Graphic Colors Setup ---
     (defvar *gc-docking-port* nil)
     (defvar *gc-ship-player* nil)
     (defvar *gc-ship-enemy* nil)
     (defvar *gc-weapon-torp* nil)
     (defvar *gc-weapon-rail* nil)
     (defvar *gc-pdc-bullets* nil)

     (defun init-game-gcs (win)
       (declare (ignore win))
       (setf *gc-docking-port* (next-resource-id)
             *gc-ship-player* (next-resource-id)
             *gc-ship-enemy* (next-resource-id)
             *gc-weapon-torp* (next-resource-id)
             *gc-weapon-rail* (next-resource-id)
             *gc-pdc-bullets* (next-resource-id))
       (create-gc *gc-docking-port* :foreground #x00ffcc00)
       (create-gc *gc-ship-player* :foreground #x0033cc33)
       (create-gc *gc-ship-enemy* :foreground #x00ff3333)
       (create-gc *gc-weapon-torp* :foreground #x00ff9900)
       (create-gc *gc-weapon-rail* :foreground #x0033ccff)
       (create-gc *gc-pdc-bullets* :foreground #x00ffffff))

     ;; --- Subsystems Structure ---
     (defstruct subsystem
       (name "")
       (health 100.0d0))

     ;; --- Game State ---
     (defstruct app-state
       ;; Rocinante relative state: #(x y vx vy)
       (ship-state (make-array 4 :element-type 'double-float :initial-contents '(0.0d0 -120.0d0 0.0d0 0.0d0)) :type (simple-array double-float (4)))
       (fuel 100.0d0)
       (crew-strain 0.0d0)
       (juice-count 3)
       (autopilot-p nil)
       (emergency-p nil)
       ;; Enemy relative state: #(x y vx vy)
       (enemy-state (make-array 4 :element-type 'double-float :initial-contents '(40.0d0 50.0d0 0.0d0 0.0d0)) :type (simple-array double-float (4)))
       ;; Enemy subsystems
       (enemy-fuel 100.0d0)
       (enemy-weapons 100.0d0)
       (enemy-radar 100.0d0)
       (enemy-reactor 100.0d0)
       ;; Firing/combat locks
       (locked-target :reactor)
       (torpedoes nil)     ;; list of (x y vx vy fuel)
       (slugs nil)         ;; list of (x y vx vy)
       (pdc-bullet nil)    ;; active bullet trail (x1 y1 x2 y2) or nil
       (player-torpedoes nil) ;; player launched torpedoes: list of (x y vx vy fuel)
       (player-slugs nil)  ;; player launched railgun slugs: list of (x y vx vy)
       ;; Solvers
       (player-solver nil)
       (enemy-solver nil)
       (predicted-path nil)
       ;; Meta game loop
       (score 0)
       (game-over-p nil)
       (victory-p nil)
       (time-seconds 0.0d0))

     ;; --- View Layout ---
     (raw "
(defun view (w h state)
  (let ((fuel (app-state-fuel state))
        (strain (app-state-crew-strain state))
        (juice (app-state-juice-count state))
        (locked (app-state-locked-target state)))
    `(panel :name :root :x 0 :y 0 :w ,w :h ,h
       (hbox :name :main-hbox :x 10 :y 10 :w ,(- w 20) :h ,(- h 20) :spacing 10
         ;; Tactical Combat Map
         (canvas :name :tactical-map
                 :xmin -150.0 :xmax 150.0 :ymin -100.0 :ymax 100.0
                 :shapes ,(compile-tactical-shapes state)
                 :glue (:natural 500 :stretch 1 :shrink 1))
         ;; Combat Dashboard
         (vbox :name :dashboard :glue (:natural 200 :stretch 0 :shrink 0) :spacing 10
           (label :name :lbl-title :text \"ROCINANTE TACCOM\")
           (label :name :lbl-fuel :text ,(format nil \"Epstein Fuel: ~,1f%\" fuel))
           (label :name :lbl-strain :text ,(format nil \"Crew G-Strain: ~,1f%\" strain))
           (label :name :lbl-juice :text ,(format nil \"Juice Stock: ~d\" juice))
           
           (hbox :name :auto-btns :glue (:natural 28 :stretch 0 :shrink 0) :spacing 5
             (button :name :btn-auto :text ,(if (app-state-autopilot-p state) \"Auto OFF\" \"Auto ON\")
                     :msg (:toggle-autopilot) :glue (:natural 90 :stretch 1 :shrink 0))
             (button :name :btn-burn :text ,(if (app-state-emergency-p state) \"Safe Burn\" \"High-G Burn\")
                     :msg (:toggle-emergency) :glue (:natural 90 :stretch 1 :shrink 0)))
           
           (button :name :btn-juice :text \"Inject Juice (Reset Gs)\" :msg (:inject-juice)
                   :glue (:natural 28 :stretch 0 :shrink 0))
           
           (label :name :lbl-weapons :text \"--- WEAPON TARGETS ---\")
           (button :name :tgt-fuel :text ,(format nil \"[1] Fuel: ~d%\" (round (app-state-enemy-fuel state)))
                   :msg (:select-target :fuel) :glue (:natural 24 :stretch 0 :shrink 0))
           (button :name :tgt-weapons :text ,(format nil \"[2] Weapons: ~d%\" (round (app-state-enemy-weapons state)))
                   :msg (:select-target :weapons) :glue (:natural 24 :stretch 0 :shrink 0))
           (button :name :tgt-radar :text ,(format nil \"[3] Radar: ~d%\" (round (app-state-enemy-radar state)))
                   :msg (:select-target :radar) :glue (:natural 24 :stretch 0 :shrink 0))
           (button :name :tgt-reactor :text ,(format nil \"[4] Reactor: ~d%\" (round (app-state-enemy-reactor state)))
                   :msg (:select-target :reactor) :glue (:natural 24 :stretch 0 :shrink 0))
           
           (hbox :name :fire-btns :glue (:natural 28 :stretch 0 :shrink 0) :spacing 5
             (button :name :btn-rail :text \"Fire Railgun\" :msg (:fire-railgun)
                     :glue (:natural 90 :stretch 1 :shrink 0))
             (button :name :btn-torp :text \"Launch Torp\" :msg (:fire-torpedo)
                     :glue (:natural 90 :stretch 1 :shrink 0)))
           
           (label :name :lbl-status :text ,(cond
                                            ((app-state-victory-p state) \"HANGAR SECURED (VICTORY)\")
                                            ((app-state-game-over-p state) \"VESSEL LOST (DEFEATED)\")
                                            ((app-state-autopilot-p state) \"AUTO PILOT ACTIVE\")
                                            (t \"MANUAL PILOT (WASD)\"))))))))
")

     ;; --- Drawing compiler ---
     (defun compile-tactical-shapes (state)
       (let ((shapes nil)
             (ship (app-state-ship-state state))
             (enemy (app-state-enemy-state state)))
         (let ((sx (aref ship 0)) (sy (aref ship 1))
               (ex (aref enemy 0)) (ey (aref enemy 1)))
           ;; 1. Draw central docking station (Target)
           (push (list :disk 0.0d0 0.0d0 5.0d0 :color *gc-docking-port*) shapes)
           (push (list :circle 0.0d0 0.0d0 15.0d0 :color *gc-shadow*) shapes)

           ;; 2. Draw PDC range boundary
           (push (list :circle sx sy 45.0d0 :color *gc-shadow*) shapes)

           ;; 3. Draw active PDC bullet trail (flak lines)
           (when (app-state-pdc-bullet state)
             (let ((bullet (app-state-pdc-bullet state)))
               (push (list :line (first bullet) (second bullet)
                                 (third bullet) (fourth bullet) :color *gc-pdc-bullets*) shapes)))

           ;; 4. Draw incoming enemy railgun tracers
           (dolist (slug (app-state-slugs state))
             (let ((x (first slug)) (y (second slug))
                   (vx (third slug)) (vy (fourth slug)))
               (push (list :disk x y 2.0d0 :color *gc-weapon-rail*) shapes)
               (push (list :line x y (+ x (* 1.5d0 vx)) (+ y (* 1.5d0 vy)) :color *gc-weapon-rail*) shapes)))

           ;; 5. Draw enemy torpedoes
           (dolist (torp (app-state-torpedoes state))
             (push (list :disk (first torp) (second torp) 3.0d0 :color *gc-weapon-torp*) shapes))

           ;; 6. Draw player launched railgun tracers
           (dolist (slug (app-state-player-slugs state))
             (let ((x (first slug)) (y (second slug))
                   (vx (third slug)) (vy (fourth slug)))
               (push (list :disk x y 2.0d0 :color *gc-ship-player*) shapes)
               (push (list :line x y (+ x (* 1.5d0 vx)) (+ y (* 1.5d0 vy)) :color *gc-ship-player*) shapes)))

           ;; 7. Draw player torpedoes
           (dolist (torp (app-state-player-torpedoes state))
             (push (list :disk (first torp) (second torp) 3.0d0 :color *gc-ship-player*) shapes))

           ;; 8. Draw autopilot horizon line (dotted guide path)
           (when (app-state-predicted-path state)
             (push (list :poly-line (app-state-predicted-path state) :color *gc-ship-player*) shapes))

           ;; 9. Draw Rocinante (Player Ship)
           (push (list :disk sx sy 4.5d0 :color *gc-ship-player*) shapes)
           (push (list :line sx sy (+ sx (* 1.5d0 (aref ship 2))) (+ sy (* 1.5d0 (aref ship 3))) :color *gc-ship-player*) shapes)

           ;; 10. Draw Enemy Cruiser (if not completely dismantled)
           (when (> (app-state-enemy-reactor state) 0.0d0)
             (push (list :disk ex ey 6.0d0 :color *gc-ship-enemy*) shapes)
             (push (list :line ex ey (+ ex (* 1.5d0 (aref enemy 2))) (+ ey (* 1.5d0 (aref enemy 3))) :color *gc-ship-enemy*) shapes))
           shapes)))

     ;; --- State update model ---
     (defun update-game-state (state msg)
       (cond
         ((eq (car msg) :toggle-autopilot)
          (setf (app-state-autopilot-p state) (not (app-state-autopilot-p state)))
          state)

         ((eq (car msg) :toggle-emergency)
          (setf (app-state-emergency-p state) (not (app-state-emergency-p state)))
          state)

         ((eq (car msg) :inject-juice)
          (when (> (app-state-juice-count state) 0)
            (decf (app-state-juice-count state))
            (setf (app-state-crew-strain state) 0.0d0))
          state)

         ((eq (car msg) :select-target)
          (setf (app-state-locked-target state) (cadr msg))
          state)

         ((eq (car msg) :fire-railgun)
          (when (> (app-state-fuel state) 2.0d0)
            (decf (app-state-fuel state) 2.0d0)
            ;; Fires an instantaneous high-velocity unguided slug targeting the enemy coordinates
            (let* ((ship (app-state-ship-state state))
                   (enemy (app-state-enemy-state state))
                   (dx (- (aref enemy 0) (aref ship 0)))
                   (dy (- (aref enemy 1) (aref ship 1)))
                   (dist (sqrt (+ (* dx dx) (* dy dy)))))
              (when (> dist 0.1d0)
                (let* ((vel-slug 120.0d0)
                       (vx (* vel-slug (/ dx dist)))
                       (vy (* vel-slug (/ dy dist))))
                  (push (list (aref ship 0) (aref ship 1) vx vy) (app-state-player-slugs state))))))
          state)

         ((eq (car msg) :fire-torpedo)
          (when (> (app-state-fuel state) 5.0d0)
            (decf (app-state-fuel state) 5.0d0)
            ;; Launch guided torpedo with 6 seconds of fuel
            (let* ((ship (app-state-ship-state state))
                   (enemy (app-state-enemy-state state))
                   (dx (- (aref enemy 0) (aref ship 0)))
                   (dy (- (aref enemy 1) (aref ship 1)))
                   (dist (sqrt (+ (* dx dx) (* dy dy)))))
              (when (> dist 0.1d0)
                (let* ((vel-torp 30.0d0)
                       (vx (* vel-torp (/ dx dist)))
                       (vy (* vel-torp (/ dy dist))))
                  (push (list (aref ship 0) (aref ship 1) vx vy 6.0d0) (app-state-player-torpedoes state))))))
          state)

         ((eq (car msg) :key-press)
          (let ((keysym (cadr msg)))
            (unless (app-state-autopilot-p state)
              (let* ((ship (app-state-ship-state state))
                     (thrust 8.0d0)
                     (ux (cond ((eq keysym :up) thrust) ((eq keysym :down) (- thrust)) (t 0.0d0)))
                     (uy (cond ((eq keysym :right) thrust) ((eq keysym :left) (- thrust)) (t 0.0d0))))
                (when (or (/= ux 0.0d0) (/= uy 0.0d0))
                  (decf (app-state-fuel state) 0.5d0)
                  (let ((ad (make-array '(4 4) :element-type 'double-float :initial-element 0.0d0))
                        (bd (make-array '(4 2) :element-type 'double-float :initial-element 0.0d0)))
                    (multiple-value-bind (a b) (compute-cw-matrices-2d 0.00113d0 0.05d0)
                      (setf ad a bd b))
                    (setf (app-state-ship-state state)
                          (propagate-state-2d ad bd ship (vector ux uy))))))))
          state)

         ((eq (car msg) :tick)
          (if (app-state-game-over-p state)
              state
              (let* ((dt 0.05d0)
                     (n 0.00113d0)
                     (ship (app-state-ship-state state))
                     (enemy (app-state-enemy-state state))
                     (ad nil) (bd nil))
                (multiple-value-bind (a b) (compute-cw-matrices-2d n dt)
                  (setf ad a bd b))
                
                ;; 1. Update timeline
                (incf (app-state-time-seconds state) dt)

                ;; 2. PDC automated defense
                (multiple-value-bind (rem-torps bullet-trail)
                    (update-pdc-defense ship (app-state-torpedoes state) 45.0d0 dt)
                  (setf (app-state-torpedoes state) rem-torps
                        (app-state-pdc-bullet state) bullet-trail))

                ;; 3. Update active weapons positions
                (setf (app-state-slugs state) (update-slugs (app-state-slugs state) ad bd dt)
                      (app-state-torpedoes state) (update-torpedoes (app-state-torpedoes state) ship ad bd dt)
                      (app-state-player-slugs state) (update-slugs (app-state-player-slugs state) ad bd dt)
                      (app-state-player-torpedoes state) (update-torpedoes (app-state-player-torpedoes state) enemy ad bd dt))

                ;; 4. Check player collisions
                (dolist (slug (app-state-slugs state))
                  (when (check-collision ship (vector (first slug) (second slug) 0.0d0 0.0d0) 4.0d0)
                    (setf (app-state-game-over-p state) t)))
                (dolist (torp (app-state-torpedoes state))
                  (when (check-collision ship (vector (first torp) (second torp) 0.0d0 0.0d0) 4.0d0)
                    (setf (app-state-game-over-p state) t)))

                ;; 5. Check enemy hits
                (when (> (app-state-enemy-reactor state) 0.0d0)
                  (let ((tgt (app-state-locked-target state)))
                    ;; Slugs check
                    (dolist (slug (app-state-player-slugs state))
                      (when (check-collision enemy (vector (first slug) (second slug) 0.0d0 0.0d0) 5.0d0)
                        (case tgt
                          (:fuel (decf (app-state-enemy-fuel state) 25.0d0))
                          (:weapons (decf (app-state-enemy-weapons state) 25.0d0))
                          (:radar (decf (app-state-enemy-radar state) 25.0d0))
                          (:reactor (decf (app-state-enemy-reactor state) 25.0d0)))))
                    ;; Torpedoes check
                    (dolist (torp (app-state-player-torpedoes state))
                      (when (check-collision enemy (vector (first torp) (second torp) 0.0d0 0.0d0) 5.0d0)
                        (case tgt
                          (:fuel (decf (app-state-enemy-fuel state) 50.0d0))
                          (:weapons (decf (app-state-enemy-weapons state) 50.0d0))
                          (:radar (decf (app-state-enemy-radar state) 50.0d0))
                          (:reactor (decf (app-state-enemy-reactor state) 50.0d0)))))))

                ;; Clip healths to zero
                (setf (app-state-enemy-fuel state) (max 0.0d0 (app-state-enemy-fuel state))
                      (app-state-enemy-weapons state) (max 0.0d0 (app-state-enemy-weapons state))
                      (app-state-enemy-radar state) (max 0.0d0 (app-state-enemy-radar state))
                      (app-state-enemy-reactor state) (max 0.0d0 (app-state-enemy-reactor state)))

                ;; 6. Solve player MPC autopilot if enabled
                (if (and (app-state-autopilot-p state) (> (app-state-fuel state) 0.0d0))
                    (let* ((u-limit (if (app-state-emergency-p state) 150.0d0 30.0d0))
                           (obs nil))
                      ;; Collect threat coordinates for avoidance bounds
                      (dolist (slug (app-state-slugs state))
                        (push (list (first slug) (second slug) 8.0d0) obs))
                      (dolist (torp (app-state-torpedoes state))
                        (push (list (first torp) (second torp) 12.0d0) obs))
                      
                      ;; Run optimal control solver
                      (multiple-value-bind (u-traj x-pred status iterations)
                          (solve-mpc-control (app-state-player-solver state) ship #(0.0d0 0.0d0) obs u-limit ship)
                        (declare (ignore status iterations))
                        (when u-traj
                          (let* ((u0 (aref u-traj 0))
                                 (ux (aref u0 0))
                                 (uy (aref u0 1))
                                 (g-force (/ (sqrt (+ (* ux ux) (* uy uy))) 9.8d0)))
                            ;; Consume fuel based on burn force
                            (decf (app-state-fuel state) (* 0.05d0 g-force))
                            ;; Apply thrusters to state
                            (setf (app-state-ship-state state) (propagate-state-2d ad bd ship (vector ux uy)))
                            ;; Accumulate G-strain if above 3G
                            (when (> g-force 3.0d0)
                              (incf (app-state-crew-strain state) (* 1.5d0 (- g-force 3.0d0))))
                            (setf (app-state-predicted-path state)
                                  (loop for k below (length x-pred)
                                        collect (list (aref (aref x-pred k) 0) (aref (aref x-pred k) 1))))))))
                    (setf (app-state-predicted-path state) nil))

                ;; 7. Solve enemy MPC behavior
                (when (and (> (app-state-enemy-reactor state) 0.0d0)
                           (> (app-state-enemy-fuel state) 0.0d0))
                  (let* ((blind-p (= (app-state-enemy-radar state) 0.0d0))
                         (tgt-pos (if blind-p
                                      #(60.0d0 60.0d0) ;; Blind target: go to safety coordinates
                                      (vector (aref ship 0) (+ (aref ship 1) 60.0d0))))
                         ;; Enemy moves to stay within range
                         (dx (- (aref tgt-pos 0) (aref enemy 0)))
                         (dy (- (aref tgt-pos 1) (aref enemy 1)))
                         (dist (sqrt (+ (* dx dx) (* dy dy))))
                         (eu (vector (if (> dist 0.1d0) (* 10.0d0 (/ dx dist)) 0.0d0)
                                     (if (> dist 0.1d0) (* 10.0d0 (/ dy dist)) 0.0d0))))
                    (setf (app-state-enemy-state state) (propagate-state-2d ad bd enemy eu))))

                ;; 8. Enemy firing logic
                (when (and (> (app-state-enemy-reactor state) 0.0d0)
                           (> (app-state-enemy-weapons state) 0.0d0)
                           (= 0 (mod (round (* (app-state-time-seconds state) 100)) 200))) ;; Fire every 2s
                  (let* ((blind-p (= (app-state-enemy-radar state) 0.0d0))
                         (dx (- (aref ship 0) (aref enemy 0)))
                         (dy (- (aref ship 1) (aref enemy 1)))
                         (dist (sqrt (+ (* dx dx) (* dy dy)))))
                    (when (and (< dist 120.0d0) (> dist 0.1d0))
                      (if (< (random 1.0d0) 0.5d0)
                          ;; Fire unguided railgun slug (curves in relative orbit)
                          (let* ((vel-slug (if blind-p 60.0d0 90.0d0))
                                 (vx (* vel-slug (/ dx dist)))
                                 (vy (* vel-slug (/ dy dist))))
                            (push (list (aref enemy 0) (aref enemy 1) vx vy) (app-state-slugs state)))
                          ;; Fire guided torpedo (locks target if not blind)
                          (let* ((vel-torp 20.0d0)
                                 (vx (* vel-torp (/ dx dist)))
                                 (vy (* vel-torp (/ dy dist))))
                            (push (list (aref enemy 0) (aref enemy 1) vx vy (if blind-p 0.0d0 8.0d0)) (app-state-torpedoes state)))))))

                ;; 9. Check crew blacking out
                (when (>= (app-state-crew-strain state) 100.0d0)
                  (setf (app-state-autopilot-p state) nil
                        (app-state-emergency-p state) nil))

                ;; 10. Check victory condition (close to docking port with low speed)
                (let* ((dist-to-port (sqrt (+ (* (aref ship 0) (aref ship 0)) (* (aref ship 1) (aref ship 1)))))
                       (speed (sqrt (+ (* (aref ship 2) (aref ship 2)) (* (aref ship 3) (aref ship 3))))))
                  (when (and (< dist-to-port 8.0d0) (< speed 2.0d0))
                    (setf (app-state-victory-p state) t)))

                ;; Keep statistics clean
                (setf (app-state-fuel state) (max 0.0d0 (app-state-fuel state)))
                (setf (app-state-crew-strain state) (max 0.0d0 (app-state-crew-strain state)))
                state)))
         (t state)))

     (defun run-game ()
       "Launch the raw socket-based X11 orbital space combat game."
       (let* ((n 15) ;; 15 stage horizon
              (ad (make-array '(4 4) :element-type 'double-float :initial-element 0.0d0))
              (bd (make-array '(4 2) :element-type 'double-float :initial-element 0.0d0))
              (q-mat (make-array '(4 4) :element-type 'double-float :initial-element 0.0d0))
              (r-mat (make-array '(2 2) :element-type 'double-float :initial-element 0.0d0)))
         ;; Dynamics Setup
         (multiple-value-bind (a b) (compute-cw-matrices-2d 0.00113d0 0.05d0)
           (setf ad a bd b))
         ;; Costs setup: penalize positions and inputs
         (setf (aref q-mat 0 0) 1.0d0
               (aref q-mat 1 1) 1.0d0
               (aref q-mat 2 2) 5.0d0
               (aref q-mat 3 3) 5.0d0
               (aref r-mat 0 0) 10.0d0
               (aref r-mat 1 1) 10.0d0)
         
         (let ((player-sol (init-mpc-solver n ad bd q-mat r-mat 30.0d0)))
           (run-gui #'update-game-state #'view
                    (make-app-state :player-solver player-sol)
                    :tick-interval 0.05d0
                    :init-fn #'init-game-gcs))))
     ))
