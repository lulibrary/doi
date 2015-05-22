//$(document).ready(function() {
    $(function() {
        var max_fields      = 10; //maximum input boxes allowed
        var wrapper         = $(".input_fields_wrap"); //Fields wrapper
        var add_creator_name_button      = $(".add_creator_name_field_button"); //Add button ID

        var x = 1; //initial text box count
        $(add_creator_name_button).click(function(e){ //on add input button click
            e.preventDefault();
            if(x < max_fields){ //max input box allowed
                x++; //text box increment
                $(wrapper).append('<div><input type="text" name="creatorName[]" placeholder="Creator Name" /><a href="#" class="remove_field">Remove</a></div>'); //add input box
            }
        });

        $(wrapper).on("click",".remove_field", function(e){ //user click on remove text
            e.preventDefault();
            $(this).parent('div').remove(); x--;
        })

       //alert("Document loaded");
    });