;***********************************************************
;						File Header
;***********************************************************

; Author: Jens Vangindertael & Max Helskens

	title "FSM"
	list p=18F2550, r=hex, n=0
	#include	<p18F2550.inc>

ID          equ 0x20
STATE       equ 0x21
NEW         equ 0x22
OLD         equ 0x23
SHIFTHIGH   equ 0x24
SHIFTLOW    equ 0x25
FLAG        equ 0x26
M1          equ 0x27
M2          equ 0x28
M3          equ 0x29
M4          equ 0x30
OLDSTATE    equ 0x31

;***********************************************************
; 					    Reset Vector
;***********************************************************

	ORG		0x800			; Reset Vector
							; When debugging:0x000; when loading: 0x800
	GOTO	START


;***********************************************************
; 					    Interrupt Vector
;***********************************************************

	ORG     0x808       ; Interrupt Vector  HIGH priority
	GOTO	inter_high	; When debugging:0x008; when loading: 0x808
    ORG     0x818       ; Interrupt Vector  HIGH priority
	GOTO	inter_low	; When debugging:0x008; when loading: 0x808

;***********************************************************
;				 Program Code Starts Here
;***********************************************************
    ORG		0x820			; When debugging:0x020; when loading: 0x820

START

    ;Configure PORTS
    clrf 	PORTA 		; clear output data latches
	movlw 	0x3F 		; initialize data direction
	movwf 	TRISA       ; RA<5:0> inputs  0011 1111

    clrf	PORTB 		; clear output data latches
	movlw 	0x00 		; RB<7:1> as outputs, RB0 is SDI
	movwf 	TRISB

    clrf	PORTC 		; clear output data latches
	movlw 	0x00	    ;
	movwf 	TRISC

    movlw 	0x00 		; Configure A/D for digital inputs 0000 1111
	movwf 	ADCON1

    movlw 	0x07 		; Configure comparators for digital input
	movwf 	CMCON

    ;Disable USB
	bcf		UCON,3		; disable USB module
	bsf		UCFG,3		; disable internal USB transceiver

    ;Timer(s) configuration
    CLRF    T0CON
    CLRF    T1CON
    BSF		INTCON, GIE		; Global Interrupt Enable
    BSF     INTCON, PEIE    ; Peripheral interrupts enabled
    BSF     INTCON, TMR0IE  ; Timer 0 interrupt enabled
	BSF		PIE1,  TMR1IE   ; Timer 1 interrupt enabled
    BSF     PIE2,  TMR3IE   ; Timer 3 interrupt enabled

    BSF     T0CON, TMR0ON   ; Timer 0 ON
	BSF		T1CON, TMR1ON	; Timer 1 ON
    BCF     T3CON, TMR3ON   ; Timer 3 ON

    BSF     T0CON, T0PS1    ; Prescaler tmr0 @ 1:16
    BSF     T0CON, T0PS0    ; 12Mhz/(256*256*16) = 11Hz (good enough)
    BCF     T1CON, T1CKPS1  ; Prescaler tmr1 @ 1:2
    BSF     T1CON, T1CKPS0  ; 12Mhz/(256*256*2) = 91Hz (around 100Hz)
                            ; Nog aanpassen zodat exact 100Hz
	CLRF	RCON			; Interrupt priority --> All high

    ;Initialisation

    movlw   0x15            ; predetermined values to let
    movwf   SHIFTHIGH       ; timer1 interrupt at exactly 100 Hz
    movlw   0xA0            ; 12Mhz/(2*60000) = 100Hz so we have to
    movwf   SHIFTLOW        ; shift timer1 5536 up = 0X15A0 (see TMR1_init)

    movlw   b'00000000'
    movwf   M1
    movlw   b'00000010'
    movwf   M2
    movlw   b'00000011'
    movwf   M3
    movlw   b'00000001'
    movwf   M4

    clrf    WREG
    clrf    NEW
    clrf    OLD
    clrf    OLDSTATE
    MOVLW   0xFF
    MOVFF   WREG,STATE


MAIN

    BTFSC   FLAG,0          ;Timer0 overflowed flag set
    CALL    Update_SW
    BTFSC   FLAG,1
    call    Update_Outputs
    GOTO    Stepper_FSM

Update_SW                   ; Move PORTA values to STATE

    CLRF    STATE           ; Clear STATE
    BTFSC   PORTA,0         ; Check PORTA,0 --> If set write to STATE,0
    BSF     STATE,0
    BTFSC   PORTA,1         ; Check PORTA,1 --> If set write to STATE,1
    BSF     STATE,1
    BTFSC   PORTA,2         ; etc...
    BSF     STATE,2
    BTFSC   PORTA,3
    BSF     STATE,3
    BCF     FLAG, 0
    
    MOVFF   WREG, STATE
    RETURN

Update_Outputs
    movff   NEW,OLD
    btfsc   ID,3            ;Auto Down if 1
    goto    auto_down_out
    btfsc   ID,2            ;AUTO Up if 1
    goto    auto_up_out
    btfsc   ID,1            ;Manual Down if 1
    goto    manual_down_out
    btfsc   ID,0            ;Manual Up if 1
    goto    manual_up_out
    clrf    PORTB           ;IDLE -> no output
    return

auto_down_out
    movff       M3,WREG
    CPFSLT      OLD
    movff       M2,PORTB
    movff       M2,WREG
    CPFSLT      OLD
    movff       M1,PORTB
    movff       M4,WREG
    CPFSLT      OLD
    movff       M3,PORTB
    movff       M1,WREG
    CPFSLT      OLD
    movff       M4,PORTB
    return

auto_up_out
    movff       M3,WREG
    CPFSLT      OLD
    movff       M4,PORTB
    movff       M2,WREG
    CPFSLT      OLD
    movff       M3,PORTB
    movff       M4,WREG
    CPFSLT      OLD
    movff       M1,PORTB
    movff       M1,WREG
    CPFSLT      OLD
    movff       M2,PORTB
    return

manual_down_out

manual_up_out




Stepper_FSM

    ;movlw   b'00000000'
    ;CPFSEQ  STATE
    goto    AutoOrManual
    movlw   0x00
    movwf   ID                  ;IDLE: ID = 00000000
    goto    Stepper_FSM

AutoOrManual
    btfss   STATE,1             ;Switch 2 = 1: AUTO
    goto    MANUAL              ;           0: MANUAL
    goto    AUTO

MANUAL
    BTFSS   STATE,0             ;Still ON?
    goto    MAIN                ;
    btfsc   STATE,1
    goto    AUTO
    btfss   OLDSTATE,2          ;Check previous value switch 3
    call    TESTMUP
    btfsc   STATE,2             ;Switch 3 changed?
    return
    movlw   0x01
    movwf   ID                  ;State manual up: ID = 00000001

    btfss   OLDSTATE,3          ;Check previous value switch 4
    call    TESTMDOWN
    btfsc   STATE,3             ;Switch 4 changed?
    return
    movlw   0x02
    movwf   ID                  ;State manual down: ID = 00000010
    return

TESTMUP
    btfss   STATE,2             ;Switch 3 changed?
    return
    movlw   0x01
    movwf   ID                  ;State manual up: ID = 00000001
    return

TESTMDOWN
    btfss   STATE,3             ;Switch 4 changed?
    return
    movlw   0x02
    movwf   ID                  ;State manual down: ID = 00000010
    return

AUTO

    BTFSS   STATE,0             ;Still ON?
    goto    MAIN                ;
    BTFSS   STATE,1             ;Still AUTO?
    goto    MANUAL              ;
    btfss   OLDSTATE,2          ;Check previous value switch 3
    call    TESTAUP
    btfsc   STATE,2             ;Switch 3 changed?
    return
    movlw   0x04
    movwf   ID                  ;State auto up: ID = 00000100

    btfss   OLDSTATE,3          ;Check previous value switch 4
    call    TESTADOWN
    btfsc   STATE,3             ;Switch 4 changed?
    return
    movlw   0x08
    movwf   ID                  ;State auto down: ID = 00001000
    return

TESTAUP
    btfss   STATE,2             ;Switch 3 changed?
    return
    movlw   0x01
    movwf   ID                  ;State auto up: ID = 00000100
    return

TESTADOWN
    btfss   STATE,3             ;Switch 4 changed?
    return
    movlw   0x08
    movwf   ID
    return                  ;State auto down: ID = 00001000

inter_high

    clrf    FLAG
    btfsc   INTCON, TMR0IF
    bsf     FLAG,0              ;Timer0 overflowed --> Switch_FSM
    btfsc   PIR1, TMR1IF
    bsf     FLAG,1              ;Timer1 overflowed --> Stepper_FSM
    movff   SHIFTHIGH, TMR1H    ;Shift TMR1H
    movff   SHIFTLOW, TMR1L     ;Shift TMR1L

    BCF     INTCON, TMR0IF      ;clear IF
    BCF     PIR1,   TMR1IF      ;clear IF

    RETFIE

inter_low
    nop
    retfie

END