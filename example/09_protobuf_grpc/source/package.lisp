(defpackage :protobuf-grpc-example
  (:use :cl)
  (:export :phone-number
           :make-phone-number
           :serialize-phone-number
           :deserialize-phone-number
           :phone-number-number
           :phone-number-type
           :person
           :make-person
           :serialize-person
           :deserialize-person
           :person-name
           :person-id
           :person-email
           :person-phones
           :address-book
           :make-address-book
           :serialize-address-book
           :deserialize-address-book
           :address-book-people
           :get-people-request
           :make-get-people-request
           :serialize-get-people-request
           :deserialize-get-people-request
           :get-people-request-query
           :address-book-service
           :dispatch-address-book-service
           :start-address-book-service-server
           :add-person
           :call-add-person
           :get-people
           :call-get-people))