'*
'* A simple wrapper around a slideshow. Single items and lists are both supported.
'*

Function createPhotoPlayerScreen(context, contextIndex, viewController)
    obj = CreateObject("roAssociativeArray")
    initBaseScreen(obj, viewController)
    RegWrite("slideshow_overlay_force", "0", "preferences")

    screen = CreateObject("roSlideShow")
    screen.SetMessagePort(obj.Port)

    screen.SetUnderscan(2.5)
    screen.SetMaxUpscale(8.0)
    screen.SetDisplayMode("photo-fit")
    screen.SetPeriod(RegRead("slideshow_period", "preferences", "6").toInt())
    screen.SetTextOverlayHoldTime(RegRead("slideshow_overlay", "preferences", "2500").toInt())

    ' ljunkie - we need to iterate through the items and remove directories -- they don't play nice
    ' note: if we remove directories ( itms ) the contextIndex will be wrong - so fix it!
    if type(context) = "roArray" then
        key = context[contextIndex].key
        contextIndex = 0
        newcontext = []
        for each item in context
            if tostr(item.nodename) = "Photo" then 
                newcontext.Push(item)
            else 
                print "skipping item: " + tostr(item.nodename) + " " + tostr(item.title)
            end if
        next
        
        ' reset contextIndex if needed
        if context.count() <> newcontext.count() then 
            for index = 0 to newcontext.count() - 1 
                if key = newcontext[index].key then 
                    contextIndex = index
                    exit for
                end if
            end for
        end if

        context = newcontext
    end if
    ' end cleaning

    ' Standard screen properties
    obj.Screen = screen
    if type(context) = "roArray" then
        obj.Item = context[contextIndex]
        obj.Items = context ' ljunkie - set items for access later
        AddAccountHeaders(screen, obj.Item.server.AccessToken)
        screen.SetContentList(context)
        screen.SetNext(contextIndex, true)
    else
        obj.Item = context
        AddAccountHeaders(screen, obj.Item.server.AccessToken)
        screen.AddContent(context)
        screen.SetNext(0, true)
    end if

    obj.IsPaused = false
    obj.ForceResume = false
    m.ViewController.AudioPlayer.focusedbutton = 0

    obj.HandleMessage = photoPlayerHandleMessage

    obj.playbackTimer = createTimer()

    return obj
End Function

Function photoPlayerHandleMessage(msg) As Boolean
    ' We don't actually need to do much of anything, the slideshow pretty much
    ' runs itself.

    handled = false

    if type(msg) = "roSlideShowEvent" then
        handled = true

        if msg.isScreenClosed() then
            ' Send an analytics event
            RegWrite("slideshow_overlay_force", "0", "preferences")
            amountPlayed = m.playbackTimer.GetElapsedSeconds()
            Debug("Sending analytics event, appear to have watched slideshow for " + tostr(amountPlayed) + " seconds")
            m.ViewController.Analytics.TrackEvent("Playback", firstOf(m.Item.ContentType, "photo"), m.Item.mediaContainerIdentifier, amountPlayed)

            m.ViewController.PopScreen(m)
        else if msg.isPlaybackPosition() then
            m.CurIndex = msg.GetIndex() ' update current index
        else if msg.isRequestFailed() then
            Debug("preload failed: " + tostr(msg.GetIndex()))
        else if msg.isRequestInterrupted() then
            Debug("preload interrupted: " + tostr(msg.GetIndex()))
        else if msg.isPaused() then
            Debug("paused")
            m.isPaused = true
        else if msg.isResumed() then
            Debug("resumed")
            m.isPaused = false
        else if msg.isRemoteKeyPressed() then
            if ((msg.isRemoteKeyPressed() AND msg.GetIndex() = 10) OR msg.isButtonInfo()) then ' ljunkie - use * for more options on focused item
                obj = m.item     
                if type(m.items) = "roArray" and m.CurIndex <> invalid then obj = m.items[m.CurIndex]
                m.forceResume = NOT (m.isPaused)
                m.screen.Pause()
                m.isPaused = true
                photoPlayerShowContextMenu(obj)
            else if msg.GetIndex() = 3 then
                ' this needs work -- but the options button (*) now works to show the title.. so maybe another day
                ol = RegRead("slideshow_overlay_force", "preferences","0")
                time = invalid            
                if ol = "0" then
                    time = 2500 ' force show overlay
                    if RegRead("slideshow_overlay", "preferences", "2500").toInt() > 0 then time = 0 'prefs to show, force NO show
                    RegWrite("slideshow_overlay_force", "1", "preferences")
                else
                    ' print "Making overlay invisible ( or set back to the perferred settings )"
                    RegWrite("slideshow_overlay_force", "0", "preferences")
                    time = RegRead("slideshow_overlay", "preferences", "2500").toInt()
               end if

               if time <> invalid then
                   if time = 0 then
                       ' print "Forcing NO overlay"
                       m.screen.SetTextOverlayHoldTime(0)
                       m.screen.SetTextOverlayIsVisible(true) 'yea, gotta set it true to set it false?
                       m.screen.SetTextOverlayIsVisible(false)
                   else 
                      ' print "Forcing Overlay"
                       m.screen.SetTextOverlayHoldTime(0)
                       m.screen.SetTextOverlayIsVisible(true)
                       Debug("sleeping " + tostr(time) + "to show overlay")
                       sleep(time) ' sleeping to show overlay, otherwise we just get a blip (even with m.screen.SetTextOverlayHoldTime(1000)
                       m.screen.SetTextOverlayIsVisible(false)
                       m.screen.SetTextOverlayHoldTime(time)
                   end if
                end if
            end if
        end if
    end if

    return handled
End Function


Sub photoPlayerShowContextMenu(obj,force_show = false)
    audioplayer = GetViewController().AudioPlayer

    ' show audio dialog if item is directory and audio is playing/paused
    if tostr(obj.nodename) = "Directory" then
        if audioplayer.IsPlaying or audioplayer.IsPaused or audioPlayer.ContextScreenID then AudioPlayer.ShowContextMenu()
        return
    end if
   
    ' do not display if audio is playing - sorry, audio dialog overrides this, maybe work more logic in later
    ' I.E. show button for this dialog from audioplayer dialog
    if NOT force_show
        if audioplayer.IsPlaying or audioplayer.IsPaused or audioPlayer.ContextScreenID then AudioPlayer.ShowContextMenu()
        return
    end if

    container = createPlexContainerForUrl(obj.server, obj.server.serverUrl, obj.key)
    if container <> invalid then
        container.getmetadata()
        print container.metadata
        print container.metadata[0].media[0]
        obj.MediaInfo = container.metadata[0].media[0]
    end if

    dialog = createBaseDialog()
    dialog.Title = "Image: " + obj.title
    dialog.text = ""

    dialog.text = dialog.text + "Camera: " + tostr(obj.mediainfo.make) + chr(10)
    dialog.text = dialog.text + "model: " + tostr(obj.mediainfo.model) + chr(10)
    dialog.text = dialog.text + "lens: " + tostr(obj.mediainfo.lens) + chr(10)
    dialog.text = dialog.text + "aperture: " + tostr(obj.mediainfo.aperture) + chr(10)
    dialog.text = dialog.text + "exposure: " + tostr(obj.mediainfo.exposure) + chr(10)
    dialog.text = dialog.text + "iso: " + tostr(obj.mediainfo.iso) + chr(10)
    dialog.text = dialog.text + "width: " + tostr(obj.mediainfo.width) + chr(10)
    dialog.text = dialog.text + "height: " + tostr(obj.mediainfo.height) + chr(10)
    dialog.text = dialog.text + "aspect: " + tostr(obj.mediainfo.aspectratio) + chr(10)
    dialog.text = dialog.text + "container: " + tostr(obj.mediainfo.container) + chr(10)


    dialog.SetButton("close", "Close")

    dialog.ParentScreen = m
    dialog.Show()
End Sub