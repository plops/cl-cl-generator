(defpackage :cl-py-generator
  (:use :cl :alexandria)
  (:export
   ;; Public API
   :emit-py
   :write-source
   :write-notebook

   ;; DSL Node Names Handled by emit-py
   :tuple :paren :paren* :ntuple :list :curly
   :dict :dict*

   :indent :body :progn :class :cell :export :space :raw

   :lambda :def

   := :+ :- :* :@ :== :<< :!= :< :> :<= :>= :>> :/ :** :// :%

   :& :^ :logand :logxor :logior :lognot
   :and :or :|\||

   :setf :incf :decf :aref :slice :dot

   :in :is :as
   :not-in :is-not

   :comment :comments :symbol
   :string

   :return

   :for :for-generator :while :if :cond :? :when :unless

   :import :import-from

   :with :try :else :finally

   :decorator :decorated :yield :yield-from :assert))
