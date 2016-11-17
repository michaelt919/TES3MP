//
// Created by koncord on 02.03.16.
//

#include "Items.hpp"
#include <apps/openmw-mp/Script/ScriptFunctions.hpp>
#include <components/openmw-mp/NetworkMessages.hpp>
#include <apps/openmw-mp/Networking.hpp>
#include <apps/openmw/mwworld/inventorystore.hpp>
#include <components/misc/stringops.hpp>

using namespace mwmp;

int ItemFunctions::GetEquipmentSize() noexcept
{
    return MWWorld::InventoryStore::Slots;
}

unsigned int ItemFunctions::GetInventorySize(unsigned short pid) noexcept
{
    Player *player;
    GET_PLAYER(pid, player, 0);

    return player->inventory.count;
}

void ItemFunctions::EquipItem(unsigned short pid, unsigned short slot, const char *itemName, unsigned int count, int health) noexcept
{
    Player *player;
    GET_PLAYER(pid, player,);

    player->EquipedItem(slot)->refid = itemName;
    player->EquipedItem(slot)->count = count;
    player->EquipedItem(slot)->health = health;
}

void ItemFunctions::UnequipItem(unsigned short pid, unsigned short slot) noexcept
{
    LOG_MESSAGE(Log::LOG_WARN, "stub");
    //ItemFunctions::EquipItem(pid, slot, "", 0);
}

void ItemFunctions::AddItem(unsigned short pid, const char* itemName, unsigned int count, int health) noexcept
{
    Player *player;
    GET_PLAYER(pid, player, );

    Item item;
    item.refid = itemName;
    item.count = count;
    item.health = health;

    player->inventorySendBuffer.items.push_back(item);
    player->inventorySendBuffer.action = Inventory::ADDITEM;
}

void ItemFunctions::RemoveItem(unsigned short pid, const char* itemName, unsigned short count) noexcept
{
    Player *player;
    GET_PLAYER(pid, player, );

    Item item;
    item.refid = itemName;
    item.count = count;

    player->inventorySendBuffer.items.clear();
    player->inventorySendBuffer.items.push_back(item);
    player->inventorySendBuffer.action = Inventory::REMOVEITEM;
}

bool ItemFunctions::HasItemEquipped(unsigned short pid, const char* itemName)
{
    Player *player;
    GET_PLAYER(pid, player, false);

    for (int slot = 0; slot < MWWorld::InventoryStore::Slots; slot++)
        if (Misc::StringUtils::ciEqual(player->EquipedItem(slot)->refid, itemName))
            return true;
    return false;
}

const char *ItemFunctions::GetEquipmentItemId(unsigned short pid, unsigned short slot) noexcept
{
    Player *player;
    GET_PLAYER(pid, player, 0);

    return player->EquipedItem(slot)->refid.c_str();
}

int ItemFunctions::GetEquipmentItemCount(unsigned short pid, unsigned short slot) noexcept
{
    Player *player;
    GET_PLAYER(pid, player, 0);

    return player->EquipedItem(slot)->count;
}

int ItemFunctions::GetEquipmentItemHealth(unsigned short pid, unsigned short slot) noexcept
{
    Player *player;
    GET_PLAYER(pid, player, 0);

    return player->EquipedItem(slot)->health;
}

const char *ItemFunctions::GetInventoryItemId(unsigned short pid, unsigned int i) noexcept
{
    Player *player;
    GET_PLAYER(pid, player, "");

    if (i >= player->inventory.count)
        return "invalid";

    return player->inventory.items.at(i).refid.c_str();
}

int ItemFunctions::GetInventoryItemCount(unsigned short pid, unsigned int i) noexcept
{
    Player *player;
    GET_PLAYER(pid, player, 0);

    return player->inventory.items.at(i).count;
}

int ItemFunctions::GetInventoryItemHealth(unsigned short pid, unsigned int i) noexcept
{
    Player *player;
    GET_PLAYER(pid, player, 0);

    return player->inventory.items.at(i).health;
}

void ItemFunctions::SendEquipment(unsigned short pid) noexcept
{
    Player *player;
    GET_PLAYER(pid, player, );

    mwmp::Networking::get().getPlayerController()->GetPacket(ID_GAME_EQUIPMENT)->Send(player, false);
    mwmp::Networking::get().getPlayerController()->GetPacket(ID_GAME_EQUIPMENT)->Send(player, true);
}

void ItemFunctions::SendInventory(unsigned short pid) noexcept
{
    Player *player;
    GET_PLAYER(pid, player, );
    std::swap(player->inventory, player->inventorySendBuffer);
    mwmp::Networking::get().getPlayerController()->GetPacket(ID_GAME_INVENTORY)->Send(player, false);
    player->inventory = std::move(player->inventorySendBuffer);
    player->inventorySendBuffer.items.clear();
}
