extends Resource

## Resource containing free look and camera tilt parameters.
## Controls camera behavior when using free look (independent head rotation).
## Create instances of this resource (.tres files) to define different free look profiles.
class_name FreeLookSettings

## Amount of camera tilt when free looking (in degrees)
## Higher values create more dramatic tilt effect when rotating head independently
@export var free_look_tilt_amount: float = 5.0

