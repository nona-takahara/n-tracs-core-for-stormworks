function AddMapLabels(peer_id)
    local ui_id = _ENV["g_savedata"].ui_id
    if _ENV["g_savedata"].ui_id then
        server.removeMapLabel(peer_id, ui_id)
    else
        ui_id = server.getMapID()
        _ENV["g_savedata"].ui_id = ui_id
    end

    server.addMapLabel(peer_id, ui_id, 1, "Hokko Station (NHB)", 1349.5, -3756.4)
    server.addMapLabel(peer_id, ui_id, 1, "Kitao Signal Station (WAK)", 2460.7, -3786.7)
    server.addMapLabel(peer_id, ui_id, 1, "Akatsuchi Station (AKA)", 2993.3, -3937.7)
    server.addMapLabel(peer_id, ui_id, 1, "Oneru Station (ONL)", 4199.4, -5787.0)
    server.addMapLabel(peer_id, ui_id, 1, "Ohkuma Station (SGN)", 5389.7, -6653.8)
    server.addMapLabel(peer_id, ui_id, 1, "Kagamigaike Station (KGM)", 6589.5, -8240.0)
    server.addMapLabel(peer_id, ui_id, 1, "Shionaghihama Station (SNH)", 6979.8, -9207.0)

    server.addMapLabel(peer_id, ui_id, 9, "CTC Center", 6996.7, -9161.2)
end
