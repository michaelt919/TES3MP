//
// Created by koncord on 07.01.16.
//

#ifndef OPENMW_PACKETEQUIPMENT_HPP
#define OPENMW_PACKETEQUIPMENT_HPP

#include <components/openmw-mp/Packets/BasePacket.hpp>

namespace mwmp
{
    class PacketEquipment : public BasePacket
    {
    public:
        PacketEquipment(RakNet::RakPeerInterface *peer);

        virtual void Packet(RakNet::BitStream *bs, BasePlayer *player, bool send);
    };
}

#endif //OPENMW_PACKETEQUIPMENT_HPP
