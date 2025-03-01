.segment "HEADER"
    ; iNES header identifier
    .byte $4E, $45, $53, $1A
    .byte 2               ; 2x 16KB PRG code
    .byte 1               ; 1x  8KB CHR data
    .byte $01, $00        ; mapper 0, vertical mirroring
  
.segment "VECTORS"
  .word nmi, reset, 0

.segment "ZEROPAGE"
  
dvdX:
  .res 1

dvdY:
  .res 1

.segment "RODATA"
spriteData:
.incbin "dvdSprite.oam"

palettes:
  ; Background Palette
  .byte $0f, $00, $00, $00
  .byte $0f, $00, $00, $00
  .byte $0f, $00, $00, $00
  .byte $0f, $00, $00, $00

  ; Sprite Palette
  .byte $0f, $20, $10, $00
  .byte $0f, $35, $15, $05
  .byte $0f, $39, $19, $09
  .byte $0f, $3C, $1C, $0C

; Pointers to each sprite Y position in memory.
positionYList:
  .byte $00, $04, $08, $0C
  .byte $10, $14, $18, $1C
  .byte $20, $24, $28, $2C
  .byte $30, $34, $38, $3C
  .byte $40, $44, $48, $4C

; Pointers to each sprite X position in memory.
positionXList:
  .byte $03, $07, $0B, $0F
  .byte $13, $17, $1B, $1F
  .byte $23, $27, $2B, $2F
  .byte $33, $37, $3B, $3F
  .byte $43, $47, $4B, $4F

spriteCount = * - positionXList

; Pointers to each sprite palette in memory.
paletteData:
  .byte $02, $06, $0A, $0E
  .byte $12, $16, $1A, $1E
  .byte $22, $26, $2A, $2E
  .byte $32, $36, $3A, $3E
  .byte $42, $46, $4A, $4E

paletteSize = * - paletteData

.segment "BSS"
sprites:
  .res $ff

palettePointers:
  .res $14

yPointer:
  .res 1

xPointer:
  .res 1

xDirection:
  .res 1

yDirection:
  .res 1

paletteIndex:
  .res 1

  ; Character memory
.segment "CHARS"
  .incbin "test.chr"

; "nes" linker config requires a STARTUP section, even if it's empty
.segment "STARTUP"

; Main code segment for the program
.segment "CODE"

reset:
  sei		; disable IRQs
  cld		; disable decimal mode
  ldx #$40
  stx $4017	; disable APU frame IRQ
  ldx #$ff 	; Set up stack
  txs		;  .
  inx		; now X = 0
  stx $2000	; disable NMI
  stx $2001 	; disable rendering
  stx $4010 	; disable DMC IRQs
  
  lda $01
  sta xDirection

  lda $01
  sta yDirection

  ;; first wait for vblank to make sure PPU is ready
vblankwait1:
  bit $2002
  bpl vblankwait1

clear_memory:
  lda #$00
  sta $0000, x
  sta $0100, x
  sta $0200, x
  sta $0300, x
  sta $0400, x
  sta $0500, x
  sta $0600, x
  sta $0700, x
  inx
  bne clear_memory

;; second wait for vblank, PPU is ready after this
vblankwait2:
  bit $2002
  bpl vblankwait2
  
main:

  load_palettes: 
    lda $2002
    lda #$3f
    sta $2006
    lda #$00
    sta $2006
    ldx #$00
  @loop:
    lda palettes, x
    sta $2007
    inx
    cpx #$20
    bne @loop
  
  ldx $00
  @loadLoop:
    lda spriteData, x
    sta sprites, x
    inx
    cpx #$50
    bne @loadLoop

  enable_rendering:
    lda #%10000000	; Enable NMI
    sta $2000
    lda #%00010000	; Enable Sprites
    sta $2001

forever:
  jmp forever

nmi:

     ; Set SPR-RAM address to 0
    ldx $00
    stx $2003

    ; Copy local sprite memory to PPU memory.
    @loop:
      lda sprites, x
      sta $2004
      inx
      cpx #$50
      bne @loop
    
    
    jsr checkHorizontalBounds
    jsr checkVerticalBounds
    
    jsr UpdateXPosition
    jsr UpdateYPosition

    rti

UpdateXPosition:

  ldx xDirection
  cpx #$00
  bne @right
  dec dvdX

  ldx $00
  @updateX:
    lda positionXList, x
    sta xPointer

    ldy xPointer
    lda sprites, y
    sec
    sbc #1
    sta sprites, y

    inx
    cpx #spriteCount
    bne @updateX

  rts

@right:
  inc dvdX

  ldx $00
  @updateXTwo:
    lda positionXList, x
    sta xPointer

    ldy xPointer
    lda sprites, y
    clc
    adc #1
    sta sprites, y

    inx
    cpx #spriteCount
    bne @updateXTwo

  rts

UpdateYPosition:

  ldx yDirection
  cpx #$00
  bne @down
  dec dvdY

  ldx $00
  @updateY:
    lda positionYList, x
    sta yPointer

    ldy yPointer
    lda sprites, y
    sec
    sbc #1
    sta sprites, y

    inx
    cpx #spriteCount
    bne @updateY

  rts

  @down:
    inc dvdY

    ldx $00
    @updateYtwo:
      lda positionYList, x
      sta yPointer

      ldy yPointer
      lda sprites, y
      clc
      adc #1
      sta sprites, y

      inx
      cpx #$14
      bne @updateYtwo

    rts

checkHorizontalBounds:

  ; If dvdX >= $F0
  lda dvdX
  cmp #$CF
  bcs @goLeft

  ; If dvdX < $0F
  lda dvdX
  cmp #$05
  bcc @goRight

  rts ; Return when dvdX is inside the boundaries.

@goLeft:
  jsr updatePaletteIndex

  lda #$00
  sta xDirection
  rts

@goRight:
  jsr updatePaletteIndex

  lda #$01
  sta xDirection
  rts

checkVerticalBounds:

  ; If dvdX >= $F0
  lda dvdY
  cmp #$C7
  bcs @goDown

  ; If dvdX < $0F
  lda dvdY
  cmp #$06
  bcc @goUp

  rts

@goDown:
  jsr updatePaletteIndex

  lda #$00
  sta yDirection
  rts

@goUp:
  jsr updatePaletteIndex
  lda #$01
  sta yDirection
  rts

updatePaletteIndex:
  
  inc paletteIndex

  ldx paletteIndex
  cpx #$04
  beq @resetPaletteIndex
  jmp testSkip

@resetPaletteIndex:
  lda #$00
  sta paletteIndex

testSkip:
  
  ldy paletteIndex
  
  ldx $00
  @loop:
    lda paletteData, x
    tay
    
    lda paletteIndex
    sta sprites, y

    inx
    cpx #paletteSize
    bne @loop
  
  rts