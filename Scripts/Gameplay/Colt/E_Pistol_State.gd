class_name EPistolState 
enum State{ReadyToFire, HammerUncocked, Reloading}

enum Actions{None, Fire, DryFire, CockHammer, EnterReload, EnterReloadUncock, ExitReload, CylinderNext, CylinderPrev, Eject, Insert, FanFire}