extends RefCounted

const ATLAS_PATH := "res://assets/sprites/tilemap_packed.png"
const ATLAS_CELL := 18

## Placeholders: coordenadas na grade (col, row) → pixels (col*18, row*18, 18, 18).
const REGION_GRASS := Rect2(0 * ATLAS_CELL, 0 * ATLAS_CELL, ATLAS_CELL, ATLAS_CELL)
const REGION_SPRING := Rect2(8 * ATLAS_CELL, 5 * ATLAS_CELL, ATLAS_CELL, ATLAS_CELL)
const REGION_LADDER := Rect2(11 * ATLAS_CELL, 2 * ATLAS_CELL, ATLAS_CELL, 2 * ATLAS_CELL)
const REGION_LUCKY := Rect2(10 * ATLAS_CELL, 0 * ATLAS_CELL, ATLAS_CELL, ATLAS_CELL)
## Ajuste os Rect2 no atlas (`tilemap_packed.png`).
const REGION_SPIKE := Rect2(8 * ATLAS_CELL, 3 * ATLAS_CELL, ATLAS_CELL, ATLAS_CELL)
const REGION_COIN := Rect2(11 * ATLAS_CELL, 7 * ATLAS_CELL, ATLAS_CELL, ATLAS_CELL)

const ITEM_GRASS := "GRASS"
const ITEM_SPRING := "SPRING"
const ITEM_LADDER := "LADDER"
const ITEM_LUCKY := "LUCKY"
const ITEM_SPIKE := "SPIKE"
const ITEM_COIN := "COIN"

static func region_for_item(item_id: String) -> Rect2:
	match item_id:
		ITEM_GRASS:
			return REGION_GRASS
		ITEM_SPRING:
			return REGION_SPRING
		ITEM_LADDER:
			return REGION_LADDER
		ITEM_LUCKY:
			return REGION_LUCKY
		ITEM_SPIKE:
			return REGION_SPIKE
		ITEM_COIN:
			return REGION_COIN
		_:
			return REGION_GRASS

## Nome curto nos botões da UI (fase de escolha).
static func label_for_item(item_id: String) -> String:
	match item_id:
		ITEM_GRASS:
			return "Terra"
		ITEM_SPRING:
			return "Mola"
		ITEM_LADDER:
			return "Escada"
		ITEM_LUCKY:
			return "Lucky"
		ITEM_SPIKE:
			return "Espinho"
		ITEM_COIN:
			return "Moeda"
		_:
			return item_id
