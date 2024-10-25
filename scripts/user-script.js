
function checkPosition () {
    var position = mp.get_property_number( 'percent-pos', 0 );
    if ( position >= 95 ) {
        // os.execute( 'D:\\Mega\\IDEs\\AutoHotkey v2\\mpv-assistant.ahk' );
        // mp.osd_message( mp.get_property( "path" ) );
    }
}

function test () {
    mp.osd_message( 'test-js' );
}

mp.observe_property( "percent-pos", "native", checkPosition );

mp.register_script_message( "test-js", test );