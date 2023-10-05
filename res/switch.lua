CreateSwitch("NHB21", { "NHB21" }, { TrackGetter("NHB21T") })
CreateSwitch("NHB22", { "NHB22a", "NHB22b" }, { TrackGetter("NHB21T"), TrackGetter("NHB22T") })
CreateSwitch("NHB31", { "NHB31" }, { TrackGetter("NHB22T") }, true)

CreateSwitch("WAK11", { "WAK11" }, { TrackGetter("WAK1RBT"), TrackGetter("WAK11T") })
CreateSwitch("WAK12", { "WAK12" }, { TrackGetter("WAK12T") })

CreateSwitch("SGN11", { "SGN11" }, { TrackGetter("SGN1RBT"), TrackGetter("SGN11T") })
CreateSwitch("SGN12", { "SGN12" }, { TrackGetter("SGN12T") })

CreateSwitch("SNH21", { "SNH21a", "SNH21b" }, { TrackGetter("SNH21AT"), TrackGetter("SNH21BT") })
CreateSwitch("SNH22", { "SNH22" }, { TrackGetter("SNH22T") })
