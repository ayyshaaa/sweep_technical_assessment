{% test string_length(model, column_name, min, max) %}

with validation as (

    select {{ column_name }} as value
    from {{ model }}

),

validation_errors as (

    select value
    from validation
    where length(value) < {{ min }}
       or length(value) > {{ max }}

)

select * from validation_errors

{% endtest %}
