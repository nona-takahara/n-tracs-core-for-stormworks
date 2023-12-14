CreateSwitch("NHB21", { "NHB21" }, { TrackGetter("NHB21T") })
CreateSwitch("NHB22", { "NHB22a", "NHB22b" }, { TrackGetter("NHB21T"), TrackGetter("NHB22T") })
CreateSwitch("NHB31", { "NHB31" }, { TrackGetter("NHB22T") }, true)

CreateSwitch("WAK11", { "WAK11" }, { TrackGetter("WAK1RBT"), TrackGetter("WAK11T") })
CreateSwitch("WAK12", { "WAK12" }, { TrackGetter("WAK12T") })

CreateSwitch("SGN21", { "SGN21" }, { TrackGetter("SGN1RT"), TrackGetter("SGN21T") })
CreateSwitch("SGN22", { "SGN22" }, { TrackGetter("SGN22T") })

CreateSwitch("SNH21", { "SNH21a", "SNH21b" }, { TrackGetter("SNH21AT"), TrackGetter("SNH21BT") })
CreateSwitch("SNH22", { "SNH22" }, { TrackGetter("SNH22T") })
