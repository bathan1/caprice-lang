import chess
import chess.svg

# Midgame-ish starting position
fen = "r2q1rk1/ppp2ppp/2nbpn2/3p4/3P4/2NBPN2/PPP1BPPP/R2Q1RK1 w - - 0 9"

board = chess.Board(fen)

# Save original board
with open("assets/board.svg", "w") as f:
    f.write(chess.svg.board(board=board, size=500))

# Proposed move: White knight from f3 to e5
move = chess.Move.from_uci("f3e5")
board.push(move)

# Save board after proposed move
with open("assets/board-after.svg", "w") as f:
    f.write(
        chess.svg.board(
            board=board,
            size=500,
            lastmove=move,
        )
    )
