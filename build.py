from pathlib import Path
root=Path(__file__).parent
src=root/'src'
parts=['banner.lua','engine.lua','quests.lua','catalog.lua','movement.lua','adapter_base.lua','tasks.lua','advanced.lua','maritime.lua']
code=''.join((src/name).read_text() for name in parts)
code+='\n    return adapter\nend\nif POLARIS_TEST then return {newEngine=newEngine,newTransport=newTransport,chooseQuest=chooseQuest,quests=QUESTS,newAdapter=newAdapter,newCharacterController=newCharacterController,newMovement=newMovement,activities=ACTIVITIES} end\n'
code+=(src/'interface.lua').read_text()
(root/'polaris_mobile.lua').write_text(code)
print('Built',len(code.encode()),'bytes')
