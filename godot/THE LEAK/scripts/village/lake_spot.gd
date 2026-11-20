extends StaticBody3D
## Точка лагеря у озера под прицелом (промпт 20.11 18:32/18:33): тайник (пень, куст, палатка, клад) или стройплощадка.
## Сама ничего не решает — спрашивает хозяина (lake_camp.gd / lake_base.gd): spot_prompt / spot_use.
var host          # lake_camp.gd или lake_base.gd
var idx := 0


## Текст подсказки под прицелом.
func get_prompt(g) -> String:
	return host.spot_prompt(self, g)


## [F] — обыскать / построить.
func interact(g) -> void:
	host.spot_use(self, g)
